#!/bin/bash

# Автоматическое получение сертификата из панели и установка на ноду

echo "🔧 Автоматическая установка сертификата из панели на ноду"
echo "=========================================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"

# Получение учетных данных
ADMIN_USERNAME=$(grep -E "^SUDO_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)
ADMIN_PASSWORD=$(grep -E "^SUDO_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "❌ Не удалось найти учетные данные"
    exit 1
fi

echo "1️⃣  Получение токена админа..."
TOKEN=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import urllib.parse
import json
import ssl
import time

ssl._create_default_https_context = ssl._create_unverified_context

for attempt in range(5):
    try:
        data = urllib.parse.urlencode({'username': '$ADMIN_USERNAME', 'password': '$ADMIN_PASSWORD'}).encode()
        req = urllib.request.Request('http://localhost:62050/api/admin/token', data=data)
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        
        with urllib.request.urlopen(req, timeout=15) as response:
            if response.status == 200:
                result = json.loads(response.read().decode())
                token = result.get('access_token', '')
                if token:
                    print(token)
                    exit(0)
    except Exception as e:
        if attempt < 4:
            time.sleep(3)
            continue
        print(f'ERROR: {e}')
        exit(1)
" 2>&1)

if [ -z "$TOKEN" ] || [[ "$TOKEN" == ERROR* ]]; then
    echo "❌ Не удалось получить токен: $TOKEN"
    exit 1
fi

echo "✅ Токен получен"
echo ""

echo "2️⃣  Получение информации о ноде..."
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

try:
    with GetDB() as db:
        node = db.query(Node).filter(Node.address == '$NODE_IP').first()
        if not node:
            node = db.query(Node).first()
        
        if node:
            print(f\"{node.id}\")
        else:
            print('ERROR: No nodes found')
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1)

if [[ "$NODE_INFO" == ERROR* ]]; then
    echo "❌ Ошибка: $NODE_INFO"
    exit 1
fi

NODE_ID="$NODE_INFO"
echo "   Найдена нода ID: $NODE_ID"
echo ""

echo "3️⃣  Скачивание сертификата из панели..."
CERT_CONTENT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl
import time

ssl._create_default_https_context = ssl._create_unverified_context

token = '$TOKEN'
node_id = $NODE_ID
max_retries = 5

for attempt in range(max_retries):
    try:
        req = urllib.request.Request(f'http://localhost:62050/api/node/{node_id}/certificate')
        req.add_header('Authorization', f'Bearer {token}')
        
        with urllib.request.urlopen(req, timeout=15) as response:
            if response.status == 200:
                result = json.loads(response.read().decode())
                cert = result.get('certificate', '')
                if cert and 'BEGIN CERTIFICATE' in cert:
                    print(cert)
                    exit(0)
                else:
                    print(f'ERROR: Invalid certificate format', file=__import__('sys').stderr)
            else:
                error_text = response.read().decode()
                print(f'ERROR: HTTP {response.status}: {error_text[:200]}', file=__import__('sys').stderr)
    except Exception as e:
        if attempt < max_retries - 1:
            time.sleep(2)
            continue
        print(f'ERROR: {type(e).__name__}: {str(e)[:200]}', file=__import__('sys').stderr)

exit(1)
" 2>&1)

if [ -z "$CERT_CONTENT" ] || [[ "$CERT_CONTENT" == ERROR* ]] || [ ! "$(echo "$CERT_CONTENT" | grep -c "BEGIN CERTIFICATE")" -gt 0 ]; then
    echo "❌ Не удалось скачать сертификат из панели"
    echo "   Ошибка: $CERT_CONTENT"
    exit 1
fi

echo "✅ Сертификат скачан ($(echo "$CERT_CONTENT" | wc -c) байт)"
echo ""

echo "4️⃣  Установка сертификата на ноду..."
echo "$CERT_CONTENT" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'cat > /var/lib/marzban-node/ssl/certificate.pem'" 2>&1 | grep -v "password:"

if [ $? -eq 0 ]; then
    echo "✅ Сертификат установлен на ноде"
else
    echo "❌ Ошибка при установке сертификата на ноду"
    exit 1
fi

echo ""

echo "5️⃣  Проверка соответствия сертификата и ключа на ноде..."
CERT_KEY_MATCH=$(ssh root@$NODE_IP "docker exec anomaly-node sh -c '
CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem
KEY_FILE=/var/lib/marzban-node/node-certs/key.pem

if [ -f \"\$CERT_FILE\" ] && [ -f \"\$KEY_FILE\" ]; then
    CERT_MOD=\$(openssl x509 -noout -modulus -in \"\$CERT_FILE\" 2>/dev/null)
    KEY_MOD=\$(openssl rsa -noout -modulus -in \"\$KEY_FILE\" 2>/dev/null)
    
    if [ \"\$CERT_MOD\" = \"\$KEY_MOD\" ]; then
        echo \"MATCH\"
    else
        echo \"MISMATCH\"
    fi
else
    echo \"NOT_FOUND\"
fi
'" 2>&1 | grep -v "password:" | tail -1)

if [ "$CERT_KEY_MATCH" = "MATCH" ]; then
    echo "   ✅ Сертификат и ключ теперь совпадают!"
else
    echo "   ❌ Сертификат и ключ все еще не совпадают"
    echo "   💡 Возможно, нужно пересоздать ноду с новым сертификатом"
    exit 1
fi

echo ""

echo "6️⃣  Перезапуск ноды..."
ssh root@$NODE_IP "cd /opt/Anomaly && docker-compose -f docker-compose.node.yml restart anomaly-node" 2>&1 | grep -v "password:"
sleep 10

echo ""

echo "7️⃣  Синхронизация сертификата и ключа с ноды в базу данных..."
./sync-cert-and-key-from-node.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Исправление завершено!"
    echo ""
    echo "💡 Следующие шаги:"
    echo "   1. Подождите 30-60 секунд"
    echo "   2. Откройте панель: https://panel.anomaly-connect.online"
    echo "   3. Перейдите в Nodes → Node 1"
    echo "   4. Нажмите 'Переподключиться'"
    echo "   5. Проверьте статус ноды"
else
    echo ""
    echo "⚠️  Синхронизация завершилась с ошибкой, но сертификат установлен"
    echo "   Попробуйте нажать 'Переподключиться' в панели"
fi


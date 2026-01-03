#!/bin/bash

# Полная диагностика системы Anomaly VPN

echo "🔍 Полная диагностика системы Anomaly VPN"
echo "=========================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"

echo "📋 Параметры системы:"
echo "   Control Server: $(hostname)"
echo "   Node Server: $NODE_IP"
echo ""

# 1. Проверка статуса всех сервисов
echo "1️⃣  Проверка статуса Docker сервисов..."
docker-compose ps
echo ""

# 2. Проверка Marzban
echo "2️⃣  Проверка Marzban..."
echo "   Статус контейнера:"
docker-compose ps marzban
echo ""
echo "   Последние логи (ошибки):"
docker-compose logs --tail=30 marzban | grep -i "error\|exception\|failed" | tail -10 || echo "   Нет ошибок в последних логах"
echo ""

# 3. Проверка получения токена
echo "3️⃣  Проверка получения токена админа..."
ADMIN_USERNAME=$(grep -E "^SUDO_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)
ADMIN_PASSWORD=$(grep -E "^SUDO_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "   ❌ Учетные данные не найдены"
else
    echo "   ✅ Учетные данные найдены"
    
    TOKEN=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import urllib.parse
import json
import ssl
import time

ssl._create_default_https_context = ssl._create_unverified_context

for attempt in range(3):
    try:
        data = urllib.parse.urlencode({'username': '$ADMIN_USERNAME', 'password': '$ADMIN_PASSWORD'}).encode()
        req = urllib.request.Request('http://localhost:62050/api/admin/token', data=data)
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                result = json.loads(response.read().decode())
                token = result.get('access_token', '')
                if token:
                    print(token)
                    exit(0)
    except Exception as e:
        if attempt < 2:
            time.sleep(2)
            continue
        print(f'ERROR: {e}')
        exit(1)
" 2>&1)
    
    if [ -z "$TOKEN" ] || [[ "$TOKEN" == ERROR* ]]; then
        echo "   ❌ Не удалось получить токен: $TOKEN"
    else
        echo "   ✅ Токен получен успешно"
    fi
fi
echo ""

# 4. Проверка ноды в базе данных
echo "4️⃣  Проверка ноды в базе данных..."
NODE_DB_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
try:
    from app.db import GetDB
    from app.db.models import Node
    
    with GetDB() as db:
        nodes = db.query(Node).all()
        if nodes:
            for node in nodes:
                print(f\"ID: {node.id}, Name: {node.name}, Address: {node.address}, Port: {node.port}, API Port: {node.api_port}\")
        else:
            print('No nodes found in database')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)

if [[ "$NODE_DB_INFO" == ERROR* ]]; then
    echo "   ❌ Ошибка при запросе базы данных: $NODE_DB_INFO"
else
    echo "   ✅ Ноды в базе данных:"
    echo "$NODE_DB_INFO" | sed 's/^/      /'
fi
echo ""

# 5. Проверка API получения нод
if [ ! -z "$TOKEN" ] && [[ ! "$TOKEN" == ERROR* ]]; then
    echo "5️⃣  Проверка API получения нод..."
    NODE_API_INFO=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://localhost:62050/api/nodes')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        data = json.loads(response.read().decode())
        print(json.dumps(data, indent=2))
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    
    if [[ "$NODE_API_INFO" == ERROR* ]]; then
        echo "   ❌ Ошибка API: $NODE_API_INFO"
    else
        echo "   ✅ Ответ API:"
        echo "$NODE_API_INFO" | sed 's/^/      /'
    fi
    echo ""
    
    # 6. Проверка получения сертификата
    echo "6️⃣  Проверка получения сертификата ноды..."
    if [ ! -z "$NODE_DB_INFO" ] && [[ ! "$NODE_DB_INFO" == ERROR* ]] && [[ ! "$NODE_DB_INFO" == "No nodes"* ]]; then
        NODE_ID=$(echo "$NODE_DB_INFO" | head -1 | grep -oP 'ID: \K\d+')
        if [ ! -z "$NODE_ID" ]; then
            CERT_RESULT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://localhost:62050/api/node/$NODE_ID/certificate')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        if response.status == 200:
            data = json.loads(response.read().decode())
            cert = data.get('certificate', '')
            if cert and 'BEGIN CERTIFICATE' in cert:
                print(f'SUCCESS: Certificate length: {len(cert)} bytes')
            else:
                print(f'ERROR: Invalid certificate format')
        else:
            error_text = response.read().decode()
            print(f'ERROR: HTTP {response.status}: {error_text[:200]}')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
            
            echo "   Результат: $CERT_RESULT"
        else
            echo "   ⚠️  Не удалось определить ID ноды"
        fi
    fi
    echo ""
fi

# 7. Проверка сертификата на ноде
echo "7️⃣  Проверка сертификата на ноде..."
NODE_CERT_CHECK=$(ssh root@$NODE_IP "docker exec anomaly-node sh -c 'if [ -f /var/lib/marzban-node/ssl/certificate.pem ]; then echo \"SUCCESS: Certificate exists\"; openssl x509 -in /var/lib/marzban-node/ssl/certificate.pem -noout -subject -dates 2>/dev/null | head -3; else echo \"ERROR: Certificate not found\"; fi'" 2>&1 | grep -v "password:")
echo "$NODE_CERT_CHECK" | sed 's/^/      /'
echo ""

# 8. Проверка ключа на ноде
echo "8️⃣  Проверка ключа на ноде..."
NODE_KEY_CHECK=$(ssh root@$NODE_IP "docker exec anomaly-node sh -c 'if [ -f /var/lib/marzban-node/node-certs/key.pem ]; then echo \"SUCCESS: Key exists\"; else echo \"ERROR: Key not found\"; fi'" 2>&1 | grep -v "password:")
echo "$NODE_KEY_CHECK" | sed 's/^/      /'
echo ""

# 9. Проверка соответствия сертификата и ключа
echo "9️⃣  Проверка соответствия сертификата и ключа на ноде..."
CERT_KEY_MATCH=$(ssh root@$NODE_IP "docker exec anomaly-node sh -c '
CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem
KEY_FILE=/var/lib/marzban-node/node-certs/key.pem

if [ -f \"\$CERT_FILE\" ] && [ -f \"\$KEY_FILE\" ]; then
    CERT_MOD=\$(openssl x509 -noout -modulus -in \"\$CERT_FILE\" 2>/dev/null)
    KEY_MOD=\$(openssl rsa -noout -modulus -in \"\$KEY_FILE\" 2>/dev/null)
    
    if [ \"\$CERT_MOD\" = \"\$KEY_MOD\" ]; then
        echo \"SUCCESS: Certificate and key MATCH\"
    else
        echo \"ERROR: Certificate and key DO NOT MATCH\"
    fi
else
    echo \"ERROR: Certificate or key file not found\"
fi
'" 2>&1 | grep -v "password:")
echo "$CERT_KEY_MATCH" | sed 's/^/      /'
echo ""

# 10. Проверка сертификата в базе данных Marzban
echo "🔟 Проверка сертификата в базе данных Marzban..."
DB_CERT_CHECK=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
try:
    from app.db import GetDB
    from app.db.models import TLS
    
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            cert_len = len(tls.certificate) if tls.certificate else 0
            key_len = len(tls.key) if tls.key else 0
            print(f'SUCCESS: Certificate in DB: {cert_len} bytes, Key in DB: {key_len} bytes')
        else:
            print('ERROR: No TLS record in database')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
echo "$DB_CERT_CHECK" | sed 's/^/      /'
echo ""

# 11. Проверка статуса ноды в панели
if [ ! -z "$TOKEN" ] && [[ ! "$TOKEN" == ERROR* ]]; then
    echo "1️⃣1️⃣  Проверка статуса ноды через API..."
    NODE_STATUS=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://localhost:62050/api/nodes')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        nodes = json.loads(response.read().decode())
        if isinstance(nodes, dict) and 'nodes' in nodes:
            nodes = nodes['nodes']
        if nodes and len(nodes) > 0:
            node = nodes[0]
            print(f\"Status: {node.get('status', 'unknown')}, Message: {node.get('message', 'none')}\")
        else:
            print('No nodes found')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    echo "   $NODE_STATUS"
    echo ""
fi

# 12. Рекомендации
echo "📋 Рекомендации:"
echo "   1. Если сертификат и ключ не совпадают:"
echo "      ./sync-cert-and-key-from-node.sh"
echo ""
echo "   2. Если сертификат не найден на ноде:"
echo "      Скачайте сертификат из панели и установите:"
echo "      ./install-node-cert.sh /path/to/cert.pem"
echo ""
echo "   3. Если нода не найдена в базе данных:"
echo "      Создайте ноду через панель или используйте auto-setup-node.sh"
echo ""

echo "✅ Диагностика завершена!"


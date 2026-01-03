#!/bin/bash

# Упрощенный скрипт для исправления KEY_VALUES_MISMATCH
# Использует прямое подключение без сложных проверок

echo "🔧 Упрощенное исправление KEY_VALUES_MISMATCH"
echo "============================================="
echo ""

NODE_IP="185.126.67.67"

# Получение учетных данных
ADMIN_USERNAME=$(grep -E "^SUDO_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)
ADMIN_PASSWORD=$(grep -E "^SUDO_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "❌ Не удалось найти учетные данные"
    exit 1
fi

echo "1️⃣  Ожидание готовности Marzban..."
sleep 5

echo "2️⃣  Получение токена..."
TOKEN=$(docker exec anomaly-marzban python3 << PYTHON_SCRIPT
import urllib.request
import urllib.parse
import json
import ssl
import time

ssl._create_default_https_context = ssl._create_unverified_context

username = '$ADMIN_USERNAME'
password = '$ADMIN_PASSWORD'

for attempt in range(5):
    try:
        data = urllib.parse.urlencode({'username': username, 'password': password}).encode()
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
        if attempt < 4:
            time.sleep(2)
            continue
        print(f'ERROR: {e}', file=__import__('sys').stderr)
        exit(1)
PYTHON_SCRIPT
)

if [ -z "$TOKEN" ] || [[ "$TOKEN" == ERROR* ]]; then
    echo "❌ Не удалось получить токен"
    echo "   Попробуйте вручную:"
    echo "   docker exec -it anomaly-marzban python3"
    echo "   Затем выполните код для получения токена"
    exit 1
fi

echo "✅ Токен получен"
echo ""

echo "3️⃣  Скачивание сертификата из панели..."
CERT_CONTENT=$(docker exec anomaly-marzban python3 << PYTHON_SCRIPT
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

token = '$TOKEN'

# Получаем список нод
req = urllib.request.Request('http://localhost:62050/api/nodes')
req.add_header('Authorization', f'Bearer {token}')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        nodes = json.loads(response.read().decode())
        if isinstance(nodes, dict) and 'nodes' in nodes:
            nodes = nodes['nodes']
        if nodes and len(nodes) > 0:
            node_id = nodes[0].get('id')
            
            # Скачиваем сертификат
            cert_req = urllib.request.Request(f'http://localhost:62050/api/node/{node_id}/certificate')
            cert_req.add_header('Authorization', f'Bearer {token}')
            
            with urllib.request.urlopen(cert_req, timeout=10) as cert_response:
                cert_data = json.loads(cert_response.read().decode())
                print(cert_data.get('certificate', ''))
        else:
            print('ERROR: No nodes found', file=__import__('sys').stderr)
            exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=__import__('sys').stderr)
    exit(1)
PYTHON_SCRIPT
)

if [ -z "$CERT_CONTENT" ] || [[ "$CERT_CONTENT" == ERROR* ]] || [ ! "$(echo "$CERT_CONTENT" | grep -c "BEGIN CERTIFICATE")" -gt 0 ]; then
    echo "❌ Не удалось скачать сертификат"
    exit 1
fi

echo "✅ Сертификат скачан"
echo ""

echo "4️⃣  Установка сертификата на ноду..."
echo "$CERT_CONTENT" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'cat > /var/lib/marzban-node/ssl/certificate.pem'" 2>&1 | grep -v "password:"

if [ $? -eq 0 ]; then
    echo "✅ Сертификат установлен"
else
    echo "❌ Ошибка при установке"
    exit 1
fi

echo ""

echo "5️⃣  Перезапуск ноды..."
ssh root@$NODE_IP "cd /opt/Anomaly && docker-compose -f docker-compose.node.yml restart anomaly-node" 2>&1 | grep -v "password:"
sleep 10

echo ""

echo "6️⃣  Синхронизация сертификата и ключа..."
./sync-cert-and-key-from-node.sh

echo ""

echo "7️⃣  Перезапуск Marzban..."
docker-compose restart marzban
sleep 10

echo ""
echo "✅ Готово! Подождите 30 секунд и нажмите 'Переподключиться' в панели"


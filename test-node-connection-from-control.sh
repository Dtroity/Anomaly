#!/bin/bash
# Тест подключения к ноде с Control Server

echo "🔍 Тест подключения к ноде с Control Server"
echo "==========================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "1️⃣  Проверка доступности ноды по сети..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "   ✅ Порт $NODE_PORT открыт на $NODE_IP"
else
    echo "   ⚠️  Порт $NODE_PORT недоступен"
fi

echo ""
echo "2️⃣  Проверка HTTPS подключения к ноде..."
HTTPS_TEST=$(timeout 5 openssl s_client -connect $NODE_IP:$NODE_PORT -verify_return_error </dev/null 2>&1 | grep -E "Verify return code|CONNECTED|depth=" | head -3)
if [ -n "$HTTPS_TEST" ]; then
    echo "   ✅ HTTPS подключение установлено"
    echo "$HTTPS_TEST" | sed 's/^/      /'
else
    echo "   ⚠️  Не удалось установить HTTPS подключение"
fi

echo ""
echo "3️⃣  Проверка через Python (как Marzban)..."
PYTHON_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import ssl
import sys

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

try:
    response = urllib.request.urlopen('https://185.126.67.67:62050/', timeout=5, context=ssl_context)
    print('SUCCESS: HTTP request successful')
    print(f'Status code: {response.getcode()}')
    print(f'Response length: {len(response.read())} bytes')
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)}')
    sys.exit(1)
" 2>&1)

if echo "$PYTHON_TEST" | grep -q "SUCCESS"; then
    echo "   ✅ Python подключение успешно"
    echo "$PYTHON_TEST" | sed 's/^/      /'
else
    echo "   ⚠️  Python подключение не удалось:"
    echo "$PYTHON_TEST" | sed 's/^/      /'
fi

echo ""
echo "4️⃣  Проверка статуса ноды в базе данных Marzban..."
NODE_STATUS=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

with GetDB() as db:
    node = db.query(Node).filter(Node.name == 'Node 1').first()
    if node:
        print(f'Status: {node.status}')
        print(f'Message: {node.message if node.message else \"(empty)\"}')
    else:
        print('ERROR: Node 1 not found')
" 2>&1 | grep -v "UserWarning")

echo "$NODE_STATUS" | sed 's/^/   /'

echo ""
echo "✅ Тест завершен!"
echo ""
echo "💡 Если все проверки пройдены:"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online"
echo "   2. Перейдите в Nodes -> Node 1"
echo "   3. Нажмите 'Переподключиться'"
echo ""


#!/bin/bash
# Тест подключения Marzban к ноде с правильными endpoints

echo "🔍 Тест подключения Marzban к ноде"
echo "==================================="
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

# Получить токен
TOKEN=""
if [ -f .env.marzban ]; then
    ADMIN_USERNAME=$(grep "^SUDO_USERNAME=" .env.marzban | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_USERNAME=" .env.marzban | cut -d'=' -f2 | tr -d '"')
    ADMIN_PASSWORD=$(grep "^SUDO_PASSWORD=" .env.marzban | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_PASSWORD=" .env.marzban | cut -d'=' -f2 | tr -d '"')
fi

if [ -z "$ADMIN_USERNAME" ] && [ -f .env ]; then
    ADMIN_USERNAME=$(grep "^SUDO_USERNAME=" .env | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_USERNAME=" .env | cut -d'=' -f2 | tr -d '"')
    ADMIN_PASSWORD=$(grep "^SUDO_PASSWORD=" .env | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_PASSWORD=" .env | cut -d'=' -f2 | tr -d '"')
fi

if [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ]; then
    TOKEN_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request, urllib.parse, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://marzban:62050/api/admin/token')
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    data = urllib.parse.urlencode({'username': '$ADMIN_USERNAME', 'password': '$ADMIN_PASSWORD'}).encode()
    with urllib.request.urlopen(req, data=data, timeout=5, context=ssl_context) as resp:
        result = json.loads(resp.read().decode())
        print(result.get('access_token', ''))
except Exception as e:
    print('ERROR:', str(e))
" 2>/dev/null)
    
    if [ -n "$TOKEN_RESPONSE" ] && [ "${TOKEN_RESPONSE:0:5}" != "ERROR" ]; then
        TOKEN="$TOKEN_RESPONSE"
        echo "✅ Токен получен"
    fi
fi

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен"
    exit 1
fi

echo ""
echo "📡 Тест различных методов подключения к ноде..."
echo ""

# Тест 1: POST /connect (как в логах ноды)
echo "1️⃣  Тест: POST /connect"
CONNECT_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/connect', method='POST')
    req.add_header('Content-Type', 'application/json')
    data = json.dumps({}).encode()
    with urllib.request.urlopen(req, data=data, timeout=10, context=ssl_context) as resp:
        status = resp.getcode()
        body = resp.read().decode()[:200]
        print(f'SUCCESS: HTTP {status} - {body}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $CONNECT_TEST"
echo ""

# Тест 2: POST / (как в логах ноды)
echo "2️⃣  Тест: POST /"
ROOT_POST_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/', method='POST')
    req.add_header('Content-Type', 'application/json')
    data = json.dumps({}).encode()
    with urllib.request.urlopen(req, data=data, timeout=10, context=ssl_context) as resp:
        status = resp.getcode()
        body = resp.read().decode()[:200]
        print(f'SUCCESS: HTTP {status} - {body}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $ROOT_POST_TEST"
echo ""

# Тест 3: GET / (как может пытаться Marzban)
echo "3️⃣  Тест: GET /"
ROOT_GET_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/')
    with urllib.request.urlopen(req, timeout=10, context=ssl_context) as resp:
        status = resp.getcode()
        body = resp.read().decode()[:200]
        print(f'SUCCESS: HTTP {status} - {body}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $ROOT_GET_TEST"
echo ""

# Тест 4: POST /ping (как в логах ноды)
echo "4️⃣  Тест: POST /ping"
PING_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/ping', method='POST')
    req.add_header('Content-Type', 'application/json')
    data = json.dumps({}).encode()
    with urllib.request.urlopen(req, data=data, timeout=10, context=ssl_context) as resp:
        status = resp.getcode()
        body = resp.read().decode()[:200]
        print(f'SUCCESS: HTTP {status} - {body}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $PING_TEST"
echo ""

echo "📋 Проверка логов ноды в реальном времени..."
echo "   Выполните на Node Server: docker logs -f anomaly-node"
echo "   Затем запустите этот скрипт снова, чтобы увидеть, какие запросы приходят"
echo ""

echo "✅ Тест завершен"
echo ""


#!/bin/bash
# Тест HTTPS подключения к ноде с Control Server

echo "🔍 Тест HTTPS подключения к ноде"
echo "================================="
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

echo "📡 Тест 1: Проверка порта..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "  ✅ Порт $NODE_PORT открыт"
else
    echo "  ❌ Порт $NODE_PORT недоступен"
    exit 1
fi

echo ""
echo "📡 Тест 2: HTTPS подключение (с игнорированием сертификата)..."
HTTPS_TEST=$(timeout 10 openssl s_client -connect "$NODE_IP:$NODE_PORT" -servername "$NODE_IP" -verify_return_error </dev/null 2>&1)
if echo "$HTTPS_TEST" | grep -q "CONNECTED"; then
    echo "  ✅ HTTPS подключение установлено"
    VERIFY_CODE=$(echo "$HTTPS_TEST" | grep "Verify return code" | head -1)
    echo "  $VERIFY_CODE"
else
    echo "  ❌ HTTPS подключение не установлено"
    echo "$HTTPS_TEST" | grep -E "error|failed|unable" | head -5
fi

echo ""
echo "📡 Тест 3: HTTP запрос к ноде (через Python с игнорированием SSL)..."
HTTP_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        status = resp.getcode()
        print(f'SUCCESS: HTTP {status}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)

if echo "$HTTP_TEST" | grep -q "SUCCESS"; then
    echo "  ✅ HTTP запрос успешен"
    echo "  $HTTP_TEST"
else
    echo "  ❌ HTTP запрос не удался"
    echo "  $HTTP_TEST"
fi

echo ""
echo "📡 Тест 4: Проверка через Marzban API..."
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
        echo "  ✅ Токен получен"
        
        # Попробовать подключиться к ноде через Marzban
        echo ""
        echo "  📊 Попытка подключения к ноде через Marzban..."
        CONNECT_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    # Попробовать подключиться напрямую к ноде
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        print('SUCCESS: Direct connection to node works')
except Exception as e:
    print(f'ERROR: Direct connection failed: {str(e)}')
" 2>/dev/null)
        
        echo "  $CONNECT_TEST"
    fi
fi

echo ""
echo "📋 Последние логи Marzban (ошибки подключения к ноде):"
docker logs anomaly-marzban --tail=50 2>&1 | grep -i -E "node|185.126.67.67|connection|ssl|tls|error|failed|unable" | tail -10 | sed 's/^/   /'

echo ""
echo "✅ Тест завершен"
echo ""
echo "💡 Если все тесты прошли успешно:"
echo "   1. Вернитесь в панель Marzban: https://panel.anomaly-connect.online"
echo "   2. Перейдите в Nodes -> Node 1"
echo "   3. Нажмите 'Переподключиться'"
echo ""


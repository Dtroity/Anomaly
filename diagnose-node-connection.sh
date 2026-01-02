#!/bin/bash
# Полная диагностика подключения ноды Marzban

echo "🔍 Полная диагностика подключения ноды Marzban"
echo "=============================================="
echo ""

# Обработка git конфликтов
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "💾 Сохранение локальных изменений..."
    git stash > /dev/null 2>&1
fi

# Обновление кода
echo "📥 Обновление кода..."
git pull > /dev/null 2>&1

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "📡 1. Проверка сетевой связности..."
echo "   Ping к ноде:"
if ping -c 3 -W 2 "$NODE_IP" > /dev/null 2>&1; then
    echo "   ✅ Нода доступна по IP"
else
    echo "   ⚠️  Ping не проходит (может быть заблокирован firewall, это нормально)"
fi

echo ""
echo "📡 2. Проверка порта ноды..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "   ✅ Порт $NODE_PORT открыт"
else
    echo "   ❌ Порт $NODE_PORT недоступен"
fi

echo ""
echo "📡 3. Проверка HTTPS подключения к ноде..."
HTTPS_TEST=$(timeout 5 openssl s_client -connect "$NODE_IP:$NODE_PORT" -servername "$NODE_IP" </dev/null 2>&1 | grep -E "Verify return code|CONNECTED|SSL handshake")
if echo "$HTTPS_TEST" | grep -q "CONNECTED"; then
    echo "   ✅ HTTPS подключение работает"
    echo "$HTTPS_TEST" | head -3 | sed 's/^/   /'
else
    echo "   ❌ HTTPS подключение не работает"
    echo "$HTTPS_TEST" | head -3 | sed 's/^/   /'
fi

echo ""
echo "📡 4. Проверка статуса ноды на Node Server..."
echo "   Выполните на Node Server:"
echo "   ssh root@$NODE_IP 'docker ps | grep anomaly-node'"
echo "   ssh root@$NODE_IP 'docker logs anomaly-node --tail=30'"
echo "   ssh root@$NODE_IP 'ls -la /var/lib/marzban-node/node-certs/'"

echo ""
echo "📡 5. Проверка через Marzban API..."

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
        echo "   ✅ Токен получен"
        
        # Получить информацию о нодах
        echo ""
        echo "   📊 Информация о нодах:"
        NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://marzban:62050/api/nodes')
    req.add_header('Authorization', f'Bearer $TOKEN')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        result = json.loads(resp.read().decode())
        if isinstance(result, list):
            nodes = result
        else:
            nodes = result.get('nodes', [])
        if nodes:
            for node in nodes:
                print(f\"Node: {node.get('name', 'N/A')}\")
                print(f\"  Address: {node.get('address', 'N/A')}\")
                print(f\"  Port: {node.get('port', 'N/A')}\")
                print(f\"  API Port: {node.get('api_port', 'N/A')}\")
                print(f\"  Status: {node.get('status', 'N/A')}\")
                print(f\"  Connected: {node.get('connected', False)}\")
        else:
            print('No nodes found')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
        
        echo "$NODE_INFO" | sed 's/^/   /'
    else
        echo "   ❌ Не удалось получить токен"
    fi
fi

echo ""
echo "📋 6. Последние логи Marzban (ошибки подключения):"
docker logs anomaly-marzban --tail=100 2>&1 | grep -i -E "node|connection|ssl|tls|error|failed|unable" | tail -15 | sed 's/^/   /'

echo ""
echo "✅ Диагностика завершена"
echo ""
echo "💡 Рекомендации:"
echo "   1. На Node Server выполните:"
echo "      ssh root@185.126.67.67"
echo "      cd /opt/Anomaly"
echo "      git pull"
echo "      chmod +x fix-node-ssl-complete.sh"
echo "      ./fix-node-ssl-complete.sh"
echo ""
echo "   2. После выполнения скрипта проверьте логи ноды:"
echo "      docker logs anomaly-node --tail=50"
echo ""
echo "   3. Убедитесь, что сертификаты установлены:"
echo "      ls -la /var/lib/marzban-node/ssl/certificate.pem"
echo "      ls -la /var/lib/marzban-node/node-certs/certificate.pem"
echo "      ls -la /var/lib/marzban-node/node-certs/key.pem"
echo ""
echo "   4. В панели Marzban нажмите 'Переподключиться'"
echo ""

#!/bin/bash
# Проверка подключения ноды с Control Server

echo "🔍 Проверка подключения ноды Marzban"
echo "====================================="
echo ""

# Проверка, на каком сервере запущен скрипт
# Control Server имеет docker-compose.yml (основной файл)
# Node Server имеет только docker-compose.node.yml

if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    echo ""
    echo "💡 Выполните на Control Server:"
    echo "   cd /opt/Anomaly"
    echo "   ./check-node-connection-from-control.sh"
    echo ""
    if [ -f docker-compose.node.yml ]; then
        echo "Или проверьте ноду напрямую:"
        echo "   docker logs anomaly-node --tail=50"
        echo "   docker exec anomaly-node ls -la /var/lib/marzban-node/node-certs/"
    fi
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

# Проверка доступности ноды по IP
NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "📡 Проверка доступности ноды..."
if ping -c 2 -W 2 "$NODE_IP" > /dev/null 2>&1; then
    echo "  ✅ Нода доступна по IP: $NODE_IP"
else
    echo "  ❌ Нода недоступна по IP: $NODE_IP"
    echo "  💡 Проверьте сетевую связность"
fi

echo ""
echo "📡 Проверка порта ноды..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "  ✅ Порт $NODE_PORT открыт"
else
    echo "  ❌ Порт $NODE_PORT недоступен"
    echo "  💡 Проверьте firewall и настройки сети"
fi

echo ""
echo "📡 Проверка через Marzban API..."

# Получить токен администратора
echo "  🔐 Получение токена администратора..."
TOKEN=""

# Попробовать получить из .env.marzban
if [ -f .env.marzban ]; then
    ADMIN_USERNAME=$(grep "^SUDO_USERNAME=" .env.marzban | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_USERNAME=" .env.marzban | cut -d'=' -f2 | tr -d '"')
    ADMIN_PASSWORD=$(grep "^SUDO_PASSWORD=" .env.marzban | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_PASSWORD=" .env.marzban | cut -d'=' -f2 | tr -d '"')
fi

# Попробовать получить из .env
if [ -z "$ADMIN_USERNAME" ] && [ -f .env ]; then
    ADMIN_USERNAME=$(grep "^SUDO_USERNAME=" .env | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_USERNAME=" .env | cut -d'=' -f2 | tr -d '"')
    ADMIN_PASSWORD=$(grep "^SUDO_PASSWORD=" .env | cut -d'=' -f2 | tr -d '"' || grep "^ADMIN_PASSWORD=" .env | cut -d'=' -f2 | tr -d '"')
fi

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "  ⚠️  Не найдены учетные данные администратора"
    echo "  💡 Введите вручную:"
    read -p "    Username: " ADMIN_USERNAME
    read -sp "    Password: " ADMIN_PASSWORD
    echo ""
fi

# Получить токен через API
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
    else
        echo "  ❌ Не удалось получить токен: $TOKEN_RESPONSE"
    fi
fi

# Проверить статус ноды через API
if [ -n "$TOKEN" ]; then
    echo ""
    echo "  📊 Проверка статуса ноды через API..."
    NODE_STATUS=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://marzban:62050/api/nodes')
    req.add_header('Authorization', f'Bearer $TOKEN')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        result = json.loads(resp.read().decode())
        nodes = result.get('nodes', [])
        if nodes:
            node = nodes[0]
            print(f\"Name: {node.get('name', 'N/A')}\")
            print(f\"Address: {node.get('address', 'N/A')}\")
            print(f\"Status: {node.get('status', 'N/A')}\")
            print(f\"Connected: {node.get('connected', False)}\")
        else:
            print('No nodes found')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
    
    if [ -n "$NODE_STATUS" ]; then
        echo "$NODE_STATUS" | while IFS= read -r line; do
            echo "    $line"
        done
    else
        echo "  ❌ Не удалось получить статус ноды"
    fi
fi

echo ""
echo "📋 Проверка логов Marzban на наличие ошибок подключения..."
docker logs anomaly-marzban --tail=50 2>&1 | grep -i -E "node|connection|ssl|tls|error|failed" | tail -10

echo ""
echo "✅ Проверка завершена"
echo ""
echo "💡 Если нода не подключается:"
echo "   1. Проверьте, что нода запущена: ssh root@$NODE_IP 'docker ps | grep anomaly-node'"
echo "   2. Проверьте логи ноды: ssh root@$NODE_IP 'docker logs anomaly-node --tail=30'"
echo "   3. Проверьте, что сертификат установлен: ssh root@$NODE_IP 'ls -la /var/lib/marzban-node/ssl/certificate.pem'"
echo "   4. В панели Marzban нажмите 'Переподключиться'"
echo ""


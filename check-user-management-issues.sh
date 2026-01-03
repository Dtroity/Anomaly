#!/bin/bash

# Скрипт для диагностики проблем с управлением пользователями в Marzban

echo "🔍 Диагностика проблем управления пользователями"
echo "================================================"
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

echo "1️⃣  Проверка статуса ноды..."
echo ""

# Получение токена админа
echo "📋 Получение токена админа..."
ADMIN_USERNAME=$(grep -E "^SUDO_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || grep -E "^ADMIN_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
ADMIN_PASSWORD=$(grep -E "^SUDO_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || grep -E "^ADMIN_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "❌ Не удалось найти учетные данные админа в .env.marzban"
    exit 1
fi

TOKEN=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import urllib.parse
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

data = urllib.parse.urlencode({'username': '$ADMIN_USERNAME', 'password': '$ADMIN_PASSWORD'}).encode()
req = urllib.request.Request('http://marzban:62050/api/admin/token', data=data)
req.add_header('Content-Type', 'application/x-www-form-urlencoded')

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode())
        print(result.get('access_token', ''))
except Exception as e:
    print('')
" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен админа"
    exit 1
fi

echo "✅ Токен получен"
echo ""

# Проверка статуса ноды
echo "2️⃣  Проверка статуса ноды в базе данных..."
NODE_STATUS=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://marzban:62050/api/nodes')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req) as response:
        nodes = json.loads(response.read().decode())
        if isinstance(nodes, dict) and 'nodes' in nodes:
            nodes = nodes['nodes']
        if nodes and len(nodes) > 0:
            node = nodes[0]
            print(f\"Status: {node.get('status', 'unknown')}, Message: {node.get('message', 'none')}\")
        else:
            print('No nodes found')
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null)

echo "   $NODE_STATUS"
echo ""

# Проверка списка пользователей
echo "3️⃣  Проверка списка пользователей..."
USERS_COUNT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://marzban:62050/api/users?limit=10')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode())
        users = result.get('users', [])
        print(len(users))
        if users:
            print('First user:', users[0].get('username', 'unknown'))
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null)

echo "   Найдено пользователей: $USERS_COUNT"
echo ""

# Проверка логов Marzban на ошибки
echo "4️⃣  Проверка логов Marzban на ошибки..."
echo "   Последние ошибки:"
docker-compose logs marzban --tail=50 | grep -i "error\|exception\|failed" | tail -10
echo ""

# Проверка логов бота
echo "5️⃣  Проверка логов бота..."
echo "   Последние ошибки:"
docker-compose logs bot --tail=50 | grep -i "error\|exception\|failed" | tail -10
echo ""

echo "✅ Диагностика завершена"
echo ""
echo "💡 Рекомендации:"
echo "   1. Если нода не подключена (status != 'connected'), это может быть причиной проблем"
echo "   2. Проверьте логи Marzban на ошибки при попытке удаления/отзыва подписки"
echo "   3. Убедитесь, что сертификат и ключ ноды синхронизированы"


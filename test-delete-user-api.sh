#!/bin/bash

# Скрипт для тестирования API удаления пользователя

echo "🧪 Тестирование API удаления пользователя"
echo "=========================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

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

# Получение списка пользователей
echo "📋 Получение списка пользователей..."
USERS=$(docker exec anomaly-marzban python3 -c "
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
        if users:
            print(users[0].get('username', ''))
        else:
            print('')
except Exception as e:
    print('')
" 2>/dev/null)

if [ -z "$USERS" ]; then
    echo "❌ Не найдено пользователей для тестирования"
    exit 1
fi

TEST_USERNAME="$USERS"
echo "   Тестовый пользователь: $TEST_USERNAME"
echo ""

# Проверка статуса ноды
echo "🔍 Проверка статуса ноды..."
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
            print(f\"{node.get('status', 'unknown')}\")
        else:
            print('no_nodes')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null)

echo "   Статус ноды: $NODE_STATUS"
echo ""

# Попытка удаления пользователя
echo "🗑️  Попытка удаления пользователя $TEST_USERNAME..."
echo ""

RESULT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://marzban:62050/api/user/$TEST_USERNAME', method='DELETE')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        if response.status == 200 or response.status == 204:
            try:
                result = json.loads(response.read().decode())
                print(f\"SUCCESS: {json.dumps(result)}\")
            except:
                print('SUCCESS: User deleted')
        else:
            error_text = response.read().decode()
            print(f\"ERROR: {response.status} - {error_text}\")
except urllib.error.HTTPError as e:
    error_text = e.read().decode() if hasattr(e, 'read') else str(e)
    print(f\"HTTP_ERROR: {e.code} - {error_text}\")
except Exception as e:
    print(f\"EXCEPTION: {type(e).__name__}: {str(e)}\")
" 2>/dev/null)

echo "   Результат: $RESULT"
echo ""

# Проверка логов Marzban
echo "📋 Последние логи Marzban (удаление пользователя):"
docker-compose logs marzban --tail=20 | grep -i "delete\|remove\|$TEST_USERNAME" | tail -10
echo ""

echo "✅ Тест завершен"


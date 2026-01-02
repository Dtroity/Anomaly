#!/bin/bash
# Manual check of Marzban inbounds

echo "🔍 Проверка inbounds в Marzban"
echo "=============================="

cd /opt/Anomaly || exit 1

# Get admin password
ADMIN_PASS=$(grep "^SUDO_PASSWORD=" .env.marzban 2>/dev/null | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)

if [ -z "$ADMIN_PASS" ]; then
    echo "❌ Пароль не найден в .env.marzban"
    exit 1
fi

# Get token
echo "🔐 Получение токена..."
TOKEN=$(docker exec anomaly-marzban python3 -c "
import urllib.request, urllib.parse, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
url = 'https://marzban:62050/api/admin/token'
data = urllib.parse.urlencode({'username': 'root', 'password': '${ADMIN_PASS}'}).encode()
req = urllib.request.Request(url, data=data, method='POST')
req.add_header('Content-Type', 'application/x-www-form-urlencoded')
with urllib.request.urlopen(req, timeout=5, context=ssl_context) as response:
    result = json.loads(response.read().decode())
    print(result.get('access_token', ''))
" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен"
    exit 1
fi

echo "✅ Токен получен"
echo ""

# Get inbounds
echo "📡 Получение inbounds..."
INBOUNDS=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
url = 'https://marzban:62050/api/inbounds'
req = urllib.request.Request(url)
req.add_header('Authorization', 'Bearer ${TOKEN}')
with urllib.request.urlopen(req, timeout=5, context=ssl_context) as response:
    result = json.loads(response.read().decode())
    print(json.dumps(result, indent=2))
" 2>/dev/null)

if [ -z "$INBOUNDS" ]; then
    echo "❌ Не удалось получить inbounds"
    exit 1
fi

echo "📋 Ответ API inbounds:"
echo "$INBOUNDS"
echo ""

# Check protocols
echo "🔍 Анализ протоколов:"
echo "$INBOUNDS" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f'Тип данных: {type(d).__name__}')
    if isinstance(d, dict):
        print(f'Ключи: {list(d.keys())}')
        for key in d.keys():
            value = d[key]
            if isinstance(value, list):
                print(f'  {key}: список из {len(value)} элементов')
            elif isinstance(value, dict):
                print(f'  {key}: словарь с ключами {list(value.keys())}')
            else:
                print(f'  {key}: {type(value).__name__}')
    else:
        print(f'Не словарь: {d}')
except Exception as e:
    print(f'Ошибка: {e}')
"


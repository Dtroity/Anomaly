#!/bin/bash
# Simplified script to fix users without proxies - uses Python for all API calls

echo "🔧 Исправление пользователей без proxies в Marzban"
echo "=================================================="

cd /opt/Anomaly || exit 1

# Handle git conflicts
if git status --porcelain fix-users-simple.sh 2>/dev/null | grep -q "fix-users-simple.sh"; then
    echo "💾 Сохранение локальных изменений..."
    git stash push -m "Auto-stash fix-users-simple" fix-users-simple.sh 2>/dev/null || true
    git pull
    git stash pop 2>/dev/null || true
fi

# Get admin credentials
ADMIN_USER="root"
ADMIN_PASS=""

if [ -f .env.marzban ]; then
    ADMIN_PASS=$(grep "^SUDO_PASSWORD=" .env.marzban | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)
fi

if [ -z "$ADMIN_PASS" ]; then
    if [ -f .env ]; then
        ADMIN_PASS=$(grep "^SUDO_PASSWORD=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)
    fi
fi

if [ -z "$ADMIN_PASS" ]; then
    echo "⚠️  Пароль не найден автоматически"
    read -sp "Введите пароль администратора Marzban: " ADMIN_PASS
    echo ""
fi

if [ -z "$ADMIN_PASS" ]; then
    echo "❌ Пароль не указан"
    exit 1
fi

echo "✅ Учетные данные получены"

# Get token using Python (Marzban uses HTTPS)
echo "🔐 Получение токена администратора..."
TOKEN_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import urllib.parse
import json
import sys
import ssl

# Disable SSL verification for internal requests
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

try:
    # Marzban uses HTTPS
    url = 'https://marzban:62050/api/admin/token'
    data = urllib.parse.urlencode({
        'username': '${ADMIN_USER}',
        'password': '${ADMIN_PASS}'
    }).encode('utf-8')
    
    req = urllib.request.Request(url, data=data, method='POST')
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as response:
        result = json.loads(response.read().decode('utf-8'))
        print(json.dumps(result))
except urllib.error.HTTPError as e:
    error_body = e.read().decode('utf-8') if e.fp else ''
    print(f'HTTP_ERROR: {e.code} - {error_body}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'ERROR: {str(e)}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

# Extract token from response
TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('access_token', ''))" 2>/dev/null)

# If failed, try from host
if [ -z "$TOKEN" ]; then
    echo "   Попытка получить токен с хоста..."
    TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:62050/api/admin/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" 2>/dev/null)
    TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('access_token', ''))" 2>/dev/null)
fi

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен"
    echo "💡 Ответ API: ${TOKEN_RESPONSE:0:300}"
    echo ""
    echo "💡 Проверьте:"
    echo "   1. Пароль в .env.marzban (SUDO_PASSWORD)"
    echo "   2. Доступность Marzban:"
    echo "      docker exec anomaly-marzban python3 -c \"import urllib.request; urllib.request.urlopen('http://marzban:62050/api/system', timeout=2)\""
    echo "   3. Попробуйте получить токен вручную:"
    echo "      curl -X POST http://localhost:62050/api/admin/token -d 'username=${ADMIN_USER}&password=ВАШ_ПАРОЛЬ'"
    exit 1
fi

echo "✅ Токен получен"

# Get inbounds to determine protocol
echo "📡 Проверка доступных протоколов..."
INBOUNDS=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import sys

try:
    url = 'http://marzban:62050/api/inbounds'
    req = urllib.request.Request(url)
    req.add_header('Authorization', 'Bearer ${TOKEN}')
    
    with urllib.request.urlopen(req, timeout=5) as response:
        result = json.loads(response.read().decode('utf-8'))
        print(json.dumps(result))
except Exception as e:
    print('{}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

# Determine protocol
PROTOCOL=""
PROXY_CONFIG=""

if echo "$INBOUNDS" | python3 -c "import sys, json; d=json.load(sys.stdin); print('vmess' if d.get('vmess') else '')" 2>/dev/null | grep -q "vmess"; then
    PROTOCOL="vmess"
    UUID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(cat /proc/sys/kernel/random/uuid)")
    PROXY_CONFIG="{\"vmess\":{\"id\":\"${UUID}\"}}"
    echo "✅ Используется протокол: VMess"
elif echo "$INBOUNDS" | python3 -c "import sys, json; d=json.load(sys.stdin); print('vless' if d.get('vless') else '')" 2>/dev/null | grep -q "vless"; then
    PROTOCOL="vless"
    UUID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(cat /proc/sys/kernel/random/uuid)")
    PROXY_CONFIG="{\"vless\":{\"id\":\"${UUID}\",\"flow\":\"\"}}"
    echo "✅ Используется протокол: VLESS"
else
    echo "❌ Не найдены доступные протоколы (vmess/vless)"
    echo "💡 Настройте inbounds в панели Marzban"
    exit 1
fi

# Get all users and fix those without proxies
echo ""
echo "👥 Поиск пользователей без proxies..."

USERS=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import sys

try:
    url = 'http://marzban:62050/api/users'
    req = urllib.request.Request(url)
    req.add_header('Authorization', 'Bearer ${TOKEN}')
    
    with urllib.request.urlopen(req, timeout=5) as response:
        result = json.loads(response.read().decode('utf-8'))
        print(json.dumps(result.get('users', [])))
except Exception as e:
    print('[]', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

FIXED_COUNT=0

echo "$USERS" | python3 -c "
import sys
import json
import urllib.request
import urllib.parse

users = json.load(sys.stdin)
fixed = 0

for user in users:
    username = user.get('username', '')
    proxies = user.get('proxies', {})
    
    if not proxies or len(proxies) == 0:
        print(f'⚠️  Пользователь {username} не имеет proxies')
        
        # Add proxies
        proxy_config = json.loads('${PROXY_CONFIG}')
        try:
            url = f'http://marzban:62050/api/user/{username}'
            data = json.dumps({'proxies': proxy_config}).encode('utf-8')
            
            req = urllib.request.Request(url, data=data, method='PUT')
            req.add_header('Authorization', 'Bearer ${TOKEN}')
            req.add_header('Content-Type', 'application/json')
            
            with urllib.request.urlopen(req, timeout=5) as response:
                result = json.loads(response.read().decode('utf-8'))
                if result.get('username') == username:
                    print(f'   ✅ Proxies добавлены')
                    fixed += 1
                else:
                    print(f'   ❌ Ошибка: {result}')
        except Exception as e:
            print(f'   ❌ Ошибка: {str(e)}')
    else:
        print(f'✅ Пользователь {username} уже имеет proxies: {list(proxies.keys())}')

print(f'FIXED:{fixed}')
" | while IFS= read -r line; do
    echo "$line"
    if [[ "$line" == "FIXED:"* ]]; then
        FIXED_COUNT=$(echo "$line" | cut -d ':' -f2)
    fi
done

echo ""
echo "✅ Готово!"
echo "📊 Исправлено пользователей: $FIXED_COUNT"
echo ""
echo "💡 Перезапустите бота: docker-compose restart bot"


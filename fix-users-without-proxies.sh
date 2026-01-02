#!/bin/bash
# Fix users in Marzban that don't have proxies configured
# This script will add proxies to all users that are missing them

echo "🔧 Исправление пользователей без proxies в Marzban"
echo "=================================================="

cd /opt/Anomaly || exit 1

# Get admin credentials
# Marzban uses SUDO_USERNAME and SUDO_PASSWORD
ADMIN_USER=""
ADMIN_PASS=""

# Check .env.marzban first (Marzban uses SUDO_USERNAME/SUDO_PASSWORD)
if [ -f .env.marzban ]; then
    ADMIN_USER=$(grep "^SUDO_USERNAME=" .env.marzban | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)
    ADMIN_PASS=$(grep "^SUDO_PASSWORD=" .env.marzban | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)
fi

# If not found, check .env
if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    if [ -f .env ]; then
        ADMIN_USER=$(grep "^SUDO_USERNAME=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)
        ADMIN_PASS=$(grep "^SUDO_PASSWORD=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" | head -1)
    fi
fi

# If still not found, try alternative names
if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    if [ -f .env.marzban ]; then
        ADMIN_USER=$(grep -E "^ADMIN_USERNAME=|^ADMIN_USER=" .env.marzban | head -1 | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        ADMIN_PASS=$(grep -E "^ADMIN_PASSWORD=|^ADMIN_PASS=" .env.marzban | head -1 | cut -d '=' -f2 | tr -d '"' | tr -d "'")
    fi
fi

# If still not found, try to get from Marzban container environment
if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "🔍 Поиск учетных данных в контейнере Marzban..."
    ADMIN_USER=$(docker exec anomaly-marzban env 2>/dev/null | grep -E "SUDO_USERNAME|ADMIN_USERNAME" | head -1 | cut -d '=' -f2 | tr -d '"' | tr -d "'" || echo "")
    ADMIN_PASS=$(docker exec anomaly-marzban env 2>/dev/null | grep -E "SUDO_PASSWORD|ADMIN_PASSWORD" | head -1 | cut -d '=' -f2 | tr -d '"' | tr -d "'" || echo "")
fi

# If still not found, use interactive prompt
if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "⚠️  Учетные данные не найдены автоматически"
    echo "💡 Убедитесь, что в .env.marzban указаны:"
    echo "   SUDO_USERNAME=root"
    echo "   SUDO_PASSWORD=ваш_пароль"
    echo ""
    echo "Или укажите учетные данные вручную:"
    read -p "Имя пользователя (по умолчанию: root): " input_user
    ADMIN_USER="${input_user:-root}"
    read -sp "Пароль: " ADMIN_PASS
    echo ""
fi

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "❌ Не найдены учетные данные администратора"
    echo "💡 Убедитесь, что в .env.marzban указаны:"
    echo "   SUDO_USERNAME=root"
    echo "   SUDO_PASSWORD=ваш_пароль"
    exit 1
fi

echo "✅ Найдены учетные данные для пользователя: $ADMIN_USER"

# Get admin token
echo "🔐 Получение токена администратора..."

# Try marzban-cli first
TOKEN=$(docker exec anomaly-marzban marzban-cli admin login --username "$ADMIN_USER" --password "$ADMIN_PASS" 2>/dev/null | grep -oP 'token=\K[^ ]+' || echo "")

# If marzban-cli failed, try API directly
if [ -z "$TOKEN" ]; then
    echo "   Попытка через API..."
    API_URL="http://localhost:62050"
    if [ -f .env.marzban ]; then
        MARZBAN_HOST=$(grep "^UVICORN_HOST=" .env.marzban | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        MARZBAN_PORT=$(grep "^UVICORN_PORT=" .env.marzban | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$MARZBAN_HOST" ] && [ -n "$MARZBAN_PORT" ]; then
            API_URL="http://${MARZBAN_HOST}:${MARZBAN_PORT}"
        fi
    fi
    
    TOKEN_RESPONSE=$(curl -s -X POST "${API_URL}/api/admin/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" 2>/dev/null)
    
    TOKEN=$(echo "$TOKEN_RESPONSE" | grep -oP '"access_token":"\K[^"]+' | head -1)
fi

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен администратора"
    echo "💡 Проверьте учетные данные:"
    echo "   SUDO_USERNAME=$ADMIN_USER"
    echo "   SUDO_PASSWORD=***"
    echo ""
    echo "💡 Попробуйте вручную:"
    echo "   docker exec -it anomaly-marzban marzban-cli admin login"
    exit 1
fi

echo "✅ Токен получен"

echo "✅ Токен получен"

# Get API URL
API_URL="http://localhost:62050"
if [ -f .env.marzban ]; then
    MARZBAN_URL=$(grep "^UVICORN_HOST=" .env.marzban | cut -d '=' -f2)
    MARZBAN_PORT=$(grep "^UVICORN_PORT=" .env.marzban | cut -d '=' -f2)
    if [ -n "$MARZBAN_URL" ] && [ -n "$MARZBAN_PORT" ]; then
        API_URL="http://${MARZBAN_URL}:${MARZBAN_PORT}"
    fi
fi

# Get available inbounds
echo "📡 Проверка доступных inbounds..."
INBOUNDS_RESPONSE=$(curl -s -X GET "${API_URL}/api/inbounds" \
    -H "Authorization: Bearer ${TOKEN}")

# Determine which protocol to use
PROTOCOL=""
PROXY_CONFIG=""

if echo "$INBOUNDS_RESPONSE" | grep -q '"vmess"'; then
    PROTOCOL="vmess"
    UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
    PROXY_CONFIG="{\"vmess\":{\"id\":\"${UUID}\"}}"
    echo "✅ Используется протокол: VMess"
elif echo "$INBOUNDS_RESPONSE" | grep -q '"vless"'; then
    PROTOCOL="vless"
    UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
    PROXY_CONFIG="{\"vless\":{\"id\":\"${UUID}\",\"flow\":\"\"}}"
    echo "✅ Используется протокол: VLESS"
elif echo "$INBOUNDS_RESPONSE" | grep -q '"trojan"'; then
    PROTOCOL="trojan"
    UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
    PROXY_CONFIG="{\"trojan\":{\"password\":\"${UUID}\"}}"
    echo "✅ Используется протокол: Trojan"
elif echo "$INBOUNDS_RESPONSE" | grep -q '"shadowsocks"'; then
    PROTOCOL="shadowsocks"
    UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
    PROXY_CONFIG="{\"shadowsocks\":{\"password\":\"${UUID}\",\"method\":\"chacha20-ietf-poly1305\"}}"
    echo "✅ Используется протокол: Shadowsocks"
else
    echo "❌ Не найдены доступные протоколы в inbounds"
    echo "💡 Настройте inbounds в панели Marzban: https://panel.anomaly-connect.online"
    exit 1
fi

# Get all users
echo ""
echo "👥 Получение списка пользователей..."
USERS_RESPONSE=$(curl -s -X GET "${API_URL}/api/users" \
    -H "Authorization: Bearer ${TOKEN}")

# Count users without proxies
FIXED_COUNT=0
TOTAL_COUNT=0

# Process each user
echo "$USERS_RESPONSE" | python3 -c "
import json
import sys
import subprocess

try:
    data = json.load(sys.stdin)
    users = data.get('users', [])
    
    for user in users:
        username = user.get('username', '')
        proxies = user.get('proxies', {})
        
        if not proxies or len(proxies) == 0:
            print(f'⚠️  Пользователь {username} не имеет proxies')
        else:
            print(f'✅ Пользователь {username} имеет proxies: {list(proxies.keys())}')
except Exception as e:
    print(f'Ошибка при обработке: {e}')
    sys.exit(1)
" | while IFS= read -r line; do
    if [[ "$line" == *"не имеет proxies"* ]]; then
        USERNAME=$(echo "$line" | grep -oP 'Пользователь \K[^ ]+')
        if [ -n "$USERNAME" ]; then
            echo "🔧 Добавление proxies для пользователя: $USERNAME"
            
            # Get current user data
            USER_DATA=$(curl -s -X GET "${API_URL}/api/user/${USERNAME}" \
                -H "Authorization: Bearer ${TOKEN}")
            
            # Update user with proxies
            UPDATE_RESPONSE=$(curl -s -X PUT "${API_URL}/api/user/${USERNAME}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"proxies\":${PROXY_CONFIG}}")
            
            if echo "$UPDATE_RESPONSE" | grep -q '"username"'; then
                echo "   ✅ Proxies добавлены"
                FIXED_COUNT=$((FIXED_COUNT + 1))
            else
                echo "   ❌ Ошибка: $UPDATE_RESPONSE"
            fi
        fi
    fi
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
done

echo ""
echo "✅ Готово!"
echo "📊 Исправлено пользователей: $FIXED_COUNT"
echo ""
echo "💡 Теперь перезапустите бота, чтобы изменения вступили в силу:"
echo "   docker-compose restart bot"


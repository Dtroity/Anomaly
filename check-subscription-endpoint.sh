#!/bin/bash
# Check subscription endpoint availability

echo "🔍 Проверка subscription endpoint"
echo "=================================="

cd /opt/Anomaly || exit 1

# Accept token as argument or try to get it automatically
if [ -n "$1" ]; then
    TOKEN="$1"
    echo "✅ Используется токен из аргумента: ${TOKEN:0:20}..."
else
    # Try to get token from Marzban API
    echo "📋 Получение тестового токена..."
    
    # Get admin token first
    ADMIN_PASS=$(grep "SUDO_PASSWORD" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -z "$ADMIN_PASS" ]; then
        ADMIN_PASS=$(grep "SUDO_PASSWORD" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
    fi
    
    if [ -n "$ADMIN_PASS" ]; then
        # Get admin token via API
        TOKEN_RESPONSE=$(curl -s -X POST "http://marzban:62050/api/admin/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=root&password=${ADMIN_PASS}")
        
        ADMIN_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -oP '"access_token":"\K[^"]+' | head -1)
        
        if [ -n "$ADMIN_TOKEN" ]; then
            # Get first user's subscription URL
            USERS_RESPONSE=$(curl -s -X GET "http://marzban:62050/api/users" \
                -H "Authorization: Bearer ${ADMIN_TOKEN}")
            
            TOKEN=$(echo "$USERS_RESPONSE" | grep -oP '"subscription_url":"/sub/\K[^"]+' | head -1)
        fi
    fi
    
    if [ -z "$TOKEN" ]; then
        echo "⚠️ Не удалось получить токен автоматически"
        echo "💡 Использование: $0 <token>"
        echo "💡 Или скопируйте токен из бота (часть после /sub/ в ссылке)"
        exit 1
    fi
    
    echo "✅ Токен получен: ${TOKEN:0:20}..."
fi

# Test basic subscription endpoint
echo ""
echo "1️⃣ Проверка базового endpoint (/sub/{token}):"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
    "http://marzban:62050/sub/${TOKEN}" || echo "❌ Ошибка подключения к Marzban"

# Test v2ray endpoint
echo ""
echo "2️⃣ Проверка V2Ray endpoint (/sub/{token}/v2ray):"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
    "http://marzban:62050/sub/${TOKEN}/v2ray" || echo "❌ Ошибка подключения к Marzban"

# Test through Nginx
echo ""
echo "3️⃣ Проверка через Nginx (https://api.anomaly-connect.online/sub/${TOKEN}/v2ray):"
curl -k -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
    "https://api.anomaly-connect.online/sub/${TOKEN}/v2ray" || echo "❌ Ошибка подключения через Nginx"

# Check if Marzban is using HTTP or HTTPS
echo ""
echo "4️⃣ Проверка протокола Marzban:"
MARZBAN_SSL=$(docker exec anomaly-marzban env | grep -i "UVICORN_SSL\|SSL" | head -3)
if [ -n "$MARZBAN_SSL" ]; then
    echo "   Marzban использует SSL/TLS"
    echo "   $MARZBAN_SSL"
else
    echo "   Marzban использует HTTP (без SSL)"
fi

# Check Marzban logs
echo ""
echo "5️⃣ Последние логи Marzban (subscription):"
docker-compose logs marzban 2>&1 | tail -20 | grep -i "sub\|subscription\|error" | tail -5 || echo "   Нет логов subscription"

# Check Nginx logs
echo ""
echo "6️⃣ Последние логи Nginx (502 errors):"
docker-compose logs nginx 2>&1 | tail -20 | grep -i "502\|bad gateway\|marzban" | tail -5 || echo "   Нет ошибок 502"

echo ""
echo "✅ Проверка завершена"


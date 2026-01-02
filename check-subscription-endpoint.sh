#!/bin/bash
# Check subscription endpoint availability

echo "🔍 Проверка subscription endpoint"
echo "=================================="

cd /opt/Anomaly || exit 1

# Get a test token (use first user's subscription URL)
echo "📋 Получение тестового токена..."
TOKEN=$(docker exec anomaly-marzban marzban-cli user list 2>/dev/null | head -5 | grep -oP '/sub/\K[^/]+' | head -1)

if [ -z "$TOKEN" ]; then
    echo "⚠️ Не удалось получить токен автоматически"
    echo "💡 Используйте токен из бота вручную"
    exit 1
fi

echo "✅ Токен: ${TOKEN:0:20}..."

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

# Check Marzban logs
echo ""
echo "4️⃣ Последние логи Marzban (subscription):"
docker-compose logs marzban --tail=20 | grep -i "sub\|subscription" | tail -5

# Check Nginx logs
echo ""
echo "5️⃣ Последние логи Nginx (502 errors):"
docker-compose logs nginx --tail=20 | grep -i "502\|bad gateway" | tail -5

echo ""
echo "✅ Проверка завершена"


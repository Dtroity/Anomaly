#!/bin/bash
# Test different subscription URL formats for V2RayTun compatibility

echo "🧪 Тестирование форматов subscription URL для V2RayTun"
echo "===================================================="

cd /opt/Anomaly || exit 1

# Get token from argument or use default
TOKEN="${1:-dXNlcl8yNzg0NTA1NzMsMTc2NzM4MjY0OAxodNMGHnlD}"

BASE_URL="https://api.anomaly-connect.online"

echo "📋 Токен: ${TOKEN:0:30}..."
echo ""

# Test 1: Base subscription URL (auto-detect)
echo "1️⃣ Базовый URL (автоопределение формата):"
echo "   ${BASE_URL}/sub/${TOKEN}"
echo "   Content-Type:"
curl -k -s -I "${BASE_URL}/sub/${TOKEN}" | grep -i "content-type" || echo "   Не удалось получить"
echo "   Первые 200 символов ответа:"
curl -k -s "${BASE_URL}/sub/${TOKEN}" | head -c 200
echo ""
echo ""

# Test 2: V2Ray endpoint (base64 encoded)
echo "2️⃣ V2Ray endpoint (/v2ray):"
echo "   ${BASE_URL}/sub/${TOKEN}/v2ray"
echo "   Content-Type:"
curl -k -s -I "${BASE_URL}/sub/${TOKEN}/v2ray" | grep -i "content-type" || echo "   Не удалось получить"
echo "   Первые 200 символов ответа:"
curl -k -s "${BASE_URL}/sub/${TOKEN}/v2ray" | head -c 200
echo ""
echo ""

# Test 3: V2Ray JSON endpoint
echo "3️⃣ V2Ray JSON endpoint (/v2ray-json):"
echo "   ${BASE_URL}/sub/${TOKEN}/v2ray-json"
echo "   Content-Type:"
curl -k -s -I "${BASE_URL}/sub/${TOKEN}/v2ray-json" | grep -i "content-type" || echo "   Не удалось получить"
echo "   Первые 200 символов ответа:"
curl -k -s "${BASE_URL}/sub/${TOKEN}/v2ray-json" | head -c 200
echo ""
echo ""

echo "✅ Тестирование завершено"
echo ""
echo "💡 Рекомендации:"
echo "   - V2RayTun обычно ожидает base64-encoded v2ray links (формат /v2ray)"
echo "   - Или JSON формат (формат /v2ray-json)"
echo "   - Базовый URL определяет формат по User-Agent"


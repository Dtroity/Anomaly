#!/bin/bash

echo "🔍 Проверка текущей конфигурации Xray"
echo "======================================"
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка, что Marzban запущен
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# Получение токена
echo "🔑 Получение токена..."
ADMIN_USER="Admin"
ADMIN_PASS=$(grep -E "MARZBAN_ADMIN_PASSWORD|SUDO_PASSWORD|ADMIN_PASSWORD" .env.marzban 2>/dev/null | cut -d'=' -f2 | head -1)

if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS=$(grep -E "MARZBAN_ADMIN_PASSWORD|SUDO_PASSWORD|ADMIN_PASSWORD" .env 2>/dev/null | cut -d'=' -f2 | head -1)
fi

if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS=$(docker exec anomaly-marzban env 2>/dev/null | grep -E "SUDO_PASSWORD|MARZBAN_ADMIN_PASSWORD" | cut -d'=' -f2 | head -1)
fi

if [ -z "$ADMIN_PASS" ]; then
    echo "  ⚠️  Пароль администратора не найден автоматически"
    read -sp "  Пароль администратора: " ADMIN_PASS
    echo ""
    if [ -z "$ADMIN_PASS" ]; then
        echo "  ❌ Пароль не введен"
        exit 1
    fi
fi

TOKEN_RESPONSE=$(curl -s -k -X POST "https://localhost:62050/api/admin/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" 2>/dev/null)

TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "  ❌ Не удалось получить токен"
    exit 1
fi

echo "  ✅ Токен получен"
echo ""

# Получение полной конфигурации
echo "📋 Получение полной конфигурации Xray..."
CONFIG=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/core/config 2>/dev/null)

if [ -z "$CONFIG" ] || echo "$CONFIG" | grep -q "detail"; then
    echo "❌ Не удалось получить конфигурацию"
    echo "Ответ: $CONFIG"
    exit 1
fi

# Сохранение в файл для анализа
echo "$CONFIG" > /tmp/xray-config-check.json
echo "✅ Конфигурация сохранена в /tmp/xray-config-check.json"
echo ""

# Проверка inbounds
echo "🔍 Проверка inbounds в конфигурации..."
INBOUNDS=$(echo "$CONFIG" | python3 -c "import sys, json; config = json.load(sys.stdin); print(json.dumps(config.get('inbounds', []), indent=2))" 2>/dev/null)

if [ -n "$INBOUNDS" ] && [ "$INBOUNDS" != "[]" ] && [ "$INBOUNDS" != "null" ]; then
    echo "✅ Inbounds найдены:"
    echo "$INBOUNDS" | python3 -m json.tool 2>/dev/null || echo "$INBOUNDS"
    echo ""
    
    # Подсчет inbounds
    INBOUND_COUNT=$(echo "$INBOUNDS" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    echo "📊 Всего inbounds: $INBOUND_COUNT"
    echo ""
    
    # Проверка протоколов
    echo "📋 Протоколы в inbounds:"
    echo "$INBOUNDS" | python3 -c "import sys, json; inbounds = json.load(sys.stdin); [print(f\"  - {inb.get('tag', 'N/A')}: {inb.get('protocol', 'N/A')}\") for inb in inbounds]" 2>/dev/null || echo "  Не удалось распарсить"
else
    echo "❌ Inbounds не найдены в конфигурации!"
    echo ""
    echo "📋 Первые 500 символов конфигурации:"
    echo "$CONFIG" | head -c 500
    echo "..."
fi

echo ""
echo "🔍 Проверка через API /api/inbounds..."
INBOUNDS_API=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/inbounds 2>/dev/null)

echo "Ответ API /api/inbounds:"
echo "$INBOUNDS_API" | python3 -m json.tool 2>/dev/null || echo "$INBOUNDS_API"
echo ""

# Проверка outbounds
echo "🔍 Проверка outbounds..."
OUTBOUNDS=$(echo "$CONFIG" | python3 -c "import sys, json; config = json.load(sys.stdin); print(json.dumps(config.get('outbounds', []), indent=2))" 2>/dev/null)

if [ -n "$OUTBOUNDS" ] && [ "$OUTBOUNDS" != "[]" ] && [ "$OUTBOUNDS" != "null" ]; then
    echo "✅ Outbounds найдены:"
    echo "$OUTBOUNDS" | python3 -m json.tool 2>/dev/null || echo "$OUTBOUNDS"
else
    echo "❌ Outbounds не найдены!"
fi

echo ""
echo "✅ Проверка завершена!"


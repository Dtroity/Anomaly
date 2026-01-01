#!/bin/bash

echo "🔍 Проверка конфигурации Xray в Marzban"
echo "========================================"

# Проверка, что Marzban запущен
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"

# Получение токена администратора
echo ""
echo "🔑 Получение токена администратора..."
TOKEN=$(docker exec anomaly-marzban marzban-cli admin login --username Admin 2>/dev/null | grep -oP 'Token: \K[^\s]+' || echo "")

if [ -z "$TOKEN" ]; then
    echo "⚠️ Не удалось получить токен автоматически"
    echo "💡 Попробуйте вручную:"
    echo "   docker exec anomaly-marzban marzban-cli admin login --username Admin"
    exit 1
fi

echo "✅ Токен получен"

# Получение текущей конфигурации
echo ""
echo "📋 Получение текущей конфигурации..."
CONFIG=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/core/config 2>/dev/null)

if [ -z "$CONFIG" ] || echo "$CONFIG" | grep -q "detail"; then
    echo "❌ Не удалось получить конфигурацию"
    echo "Ответ: $CONFIG"
    exit 1
fi

# Проверка обязательных секций
echo ""
echo "🔍 Проверка обязательных секций..."

MISSING_SECTIONS=()

if ! echo "$CONFIG" | grep -q '"inbounds"'; then
    MISSING_SECTIONS+=("inbounds")
fi

if ! echo "$CONFIG" | grep -q '"outbounds"'; then
    MISSING_SECTIONS+=("outbounds")
fi

if ! echo "$CONFIG" | grep -q '"routing"'; then
    MISSING_SECTIONS+=("routing")
fi

if ! echo "$CONFIG" | grep -q '"log"'; then
    MISSING_SECTIONS+=("log")
fi

if [ ${#MISSING_SECTIONS[@]} -gt 0 ]; then
    echo "❌ Отсутствуют обязательные секции:"
    for section in "${MISSING_SECTIONS[@]}"; do
        echo "   - $section"
    done
    echo ""
    echo "💡 Конфигурация неполная! Нужно добавить недостающие секции."
    exit 1
fi

# Проверка inbounds
echo ""
echo "📋 Проверка inbounds..."
INBOUNDS_COUNT=$(echo "$CONFIG" | grep -o '"tag"' | wc -l || echo "0")
if [ "$INBOUNDS_COUNT" -eq 0 ]; then
    echo "❌ Нет inbounds в конфигурации"
    echo "💡 Нужно добавить хотя бы один inbound (VMess, VLESS, Trojan или Shadowsocks)"
    exit 1
fi

echo "✅ Найдено inbounds: $INBOUNDS_COUNT"

# Проверка outbounds
echo ""
echo "📋 Проверка outbounds..."
OUTBOUNDS_COUNT=$(echo "$CONFIG" | grep -o '"tag".*"protocol"' | wc -l || echo "0")
if [ "$OUTBOUNDS_COUNT" -eq 0 ]; then
    echo "❌ Нет outbounds в конфигурации"
    echo "💡 Нужно добавить outbounds (direct, blocked, API)"
    exit 1
fi

echo "✅ Найдено outbounds: $OUTBOUNDS_COUNT"

# Проверка протоколов в inbounds
echo ""
echo "📋 Проверка протоколов в inbounds..."
PROTOCOLS=$(echo "$CONFIG" | grep -oP '"protocol":\s*"\K[^"]+' | grep -v "dokodemo-door" || echo "")

if [ -z "$PROTOCOLS" ]; then
    echo "⚠️ Не найдено протоколов VPN (только API inbound)"
    echo "💡 Нужно добавить inbound с протоколом: vmess, vless, trojan или shadowsocks"
else
    echo "✅ Найдены протоколы:"
    echo "$PROTOCOLS" | while read protocol; do
        echo "   - $protocol"
    done
fi

# Проверка валидности JSON
echo ""
echo "🔍 Проверка валидности JSON..."
if echo "$CONFIG" | python3 -m json.tool > /dev/null 2>&1; then
    echo "✅ JSON валиден"
else
    echo "❌ JSON невалиден!"
    echo "💡 Проверьте синтаксис конфигурации"
    exit 1
fi

echo ""
echo "✅ Конфигурация выглядит корректной!"
echo ""
echo "💡 Если в панели все еще есть ошибка, попробуйте:"
echo "   1. Нажать 'Сохранить'"
echo "   2. Нажать 'Перезагрузить ядро'"
echo "   3. Подождать 10-20 секунд"
echo "   4. Проверить логи на наличие ошибок"


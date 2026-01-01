#!/bin/bash

echo "🔍 Диагностика и исправление проблем Marzban"
echo "============================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка статуса Marzban
echo "📊 Проверка статуса Marzban..."
if ! docker ps | grep -q anomaly-marzban; then
    echo "  ❌ Marzban не запущен"
    echo "  💡 Попробуйте: docker start anomaly-marzban"
    exit 1
fi

echo "  ✅ Marzban запущен"
echo ""

# Проверка логов на ошибки
echo "📋 Проверка логов Marzban (последние 50 строк)..."
echo ""
docker logs anomaly-marzban --tail=50 2>&1 | grep -i "error\|exception\|traceback\|failed\|cannot" | tail -20
if [ ${PIPESTATUS[0]} -eq 0 ] && [ ${PIPESTATUS[1]} -eq 0 ]; then
    echo ""
    echo "  ⚠️  Найдены ошибки в логах"
else
    echo "  ✅ Критических ошибок не найдено"
fi
echo ""

# Проверка файла конфигурации
echo "🔍 Проверка файла конфигурации..."
CONFIG_PATH="/var/lib/marzban/xray_config.json"

if docker exec anomaly-marzban test -f "$CONFIG_PATH" 2>/dev/null; then
    echo "  ✅ Файл конфигурации найден: $CONFIG_PATH"
    
    # Проверка размера файла
    FILE_SIZE=$(docker exec anomaly-marzban stat -c%s "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -eq 0 ]; then
        echo "  ⚠️  Файл конфигурации пустой!"
    else
        echo "  📏 Размер файла: $FILE_SIZE байт"
    fi
    
    # Проверка валидности JSON
    echo ""
    echo "  🔍 Проверка валидности JSON..."
    if docker exec anomaly-marzban python3 -m json.tool "$CONFIG_PATH" > /dev/null 2>&1; then
        echo "  ✅ JSON валиден"
    else
        echo "  ❌ JSON невалиден!"
        echo "  💡 Конфигурация повреждена, нужно восстановить"
    fi
    
    # Проверка наличия обязательных секций
    echo ""
    echo "  🔍 Проверка обязательных секций..."
    CONFIG_CONTENT=$(docker exec anomaly-marzban cat "$CONFIG_PATH" 2>/dev/null)
    
    MISSING=()
    if ! echo "$CONFIG_CONTENT" | grep -q '"inbounds"'; then
        MISSING+=("inbounds")
    fi
    if ! echo "$CONFIG_CONTENT" | grep -q '"outbounds"'; then
        MISSING+=("outbounds")
    fi
    if ! echo "$CONFIG_CONTENT" | grep -q '"routing"'; then
        MISSING+=("routing")
    fi
    if ! echo "$CONFIG_CONTENT" | grep -q '"log"'; then
        MISSING+=("log")
    fi
    
    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "  ❌ Отсутствуют секции: ${MISSING[*]}"
    else
        echo "  ✅ Все обязательные секции присутствуют"
    fi
    
    # Проверка inbounds
    echo ""
    echo "  🔍 Проверка inbounds..."
    INBOUNDS_COUNT=$(echo "$CONFIG_CONTENT" | python3 -c "import sys, json; config = json.load(sys.stdin); print(len(config.get('inbounds', [])))" 2>/dev/null || echo "0")
    echo "  📊 Количество inbounds: $INBOUNDS_COUNT"
    
    if echo "$CONFIG_CONTENT" | grep -q '"tag".*"VMess TCP"'; then
        echo "  ✅ VMess inbound найден"
    else
        echo "  ⚠️  VMess inbound не найден"
    fi
    
    if echo "$CONFIG_CONTENT" | grep -q '"tag".*"api"'; then
        echo "  ✅ API inbound найден"
    else
        echo "  ⚠️  API inbound не найден"
    fi
else
    echo "  ❌ Файл конфигурации не найден!"
fi

echo ""
echo "💡 Рекомендации:"
echo ""
echo "  1. Если конфигурация повреждена, восстановите из backup:"
echo "     docker exec anomaly-marzban ls -la /var/lib/marzban/xray_config.json.backup.*"
echo ""
echo "  2. Или создайте новую рабочую конфигурацию:"
echo "     cd /opt/Anomaly && ./fix-xray-config-complete.sh"
echo ""
echo "  3. Проверьте логи для деталей:"
echo "     docker logs anomaly-marzban --tail=100"
echo ""


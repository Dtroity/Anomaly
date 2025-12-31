#!/bin/bash

# Скрипт для проверки доступности панели Marzban

set -e

echo "🔍 Проверка панели Marzban"
echo "=========================="
echo ""

cd /opt/Anomaly

# 1. Проверить логи Marzban
echo "📋 Логи Marzban (последние 20 строк):"
docker-compose logs --tail=20 marzban | grep -E "ERROR|WARNING|GET|POST|login|dashboard" || docker-compose logs --tail=20 marzban
echo ""

# 2. Проверить доступность Marzban напрямую
echo "🌐 Проверка доступности Marzban напрямую:"
MARZBAN_DIRECT=$(curl -s -o /dev/null -w "%{http_code}" -k https://localhost:62050/ 2>/dev/null || echo "000")
if [ "$MARZBAN_DIRECT" = "200" ] || [ "$MARZBAN_DIRECT" = "302" ] || [ "$MARZBAN_DIRECT" = "301" ]; then
    echo "  ✅ Marzban доступен напрямую (HTTP $MARZBAN_DIRECT)"
else
    echo "  ❌ Marzban недоступен напрямую (HTTP $MARZBAN_DIRECT)"
fi
echo ""

# 3. Проверить доступность через Nginx
echo "🌐 Проверка доступности через Nginx:"
PANEL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k https://panel.anomaly-connect.online/ 2>/dev/null || echo "000")
echo "  HTTP статус: $PANEL_STATUS"

# Попробовать получить содержимое
PANEL_CONTENT=$(curl -s -k https://panel.anomaly-connect.online/ 2>/dev/null | head -20)
if echo "$PANEL_CONTENT" | grep -q "login\|dashboard\|form"; then
    echo "  ✅ Форма входа найдена в HTML"
elif echo "$PANEL_CONTENT" | grep -q "html"; then
    echo "  ⚠️  HTML получен, но форма входа не найдена"
    echo "  Первые 200 символов ответа:"
    echo "$PANEL_CONTENT" | head -c 200
    echo "..."
else
    echo "  ❌ HTML не получен"
fi
echo ""

# 4. Проверить разные пути
echo "🔍 Проверка различных путей:"
for path in "/" "/dashboard/" "/login" "/dashboard/login"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "https://panel.anomaly-connect.online$path" 2>/dev/null || echo "000")
    echo "  $path: HTTP $STATUS"
done
echo ""

# 5. Проверить логи Nginx
echo "📋 Логи Nginx (последние 10 строк с panel):"
docker-compose logs --tail=50 nginx | grep -i panel | tail -10 || echo "  Нет записей о panel"
echo ""

# 6. Проверить, что Marzban слушает правильно
echo "🔍 Проверка портов Marzban:"
docker-compose exec marzban netstat -tlnp 2>/dev/null | grep 62050 || \
docker-compose exec marzban ss -tlnp 2>/dev/null | grep 62050 || \
echo "  ⚠️  Не удалось проверить порты"
echo ""

echo "✅ Проверка завершена"
echo ""
echo "💡 Попробуйте открыть:"
echo "   - https://panel.anomaly-connect.online/dashboard/"
echo "   - https://panel.anomaly-connect.online/login"
echo "   - Очистите кэш браузера (Ctrl+Shift+Delete)"


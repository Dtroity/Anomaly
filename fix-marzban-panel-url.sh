#!/bin/bash

# Скрипт для проверки и исправления URL панели Marzban

set -e

echo "🔧 Исправление URL панели Marzban"
echo "=================================="
echo ""

cd /opt/Anomaly

# 1. Проверить, что возвращает Marzban на корневом пути
echo "📋 Проверка ответа Marzban на /:"
curl -s -k https://panel.anomaly-connect.online/ 2>/dev/null | grep -i "login\|dashboard\|form\|script" | head -5 || echo "  Не найдено ключевых слов"
echo ""

# 2. Проверить /dashboard/
echo "📋 Проверка ответа Marzban на /dashboard/:"
curl -s -k https://panel.anomaly-connect.online/dashboard/ 2>/dev/null | grep -i "login\|dashboard\|form\|script" | head -5 || echo "  Не найдено ключевых слов"
echo ""

# 3. Проверить, есть ли редирект
echo "📋 Проверка редиректов:"
curl -s -I -k https://panel.anomaly-connect.online/ 2>/dev/null | grep -i "location\|http" | head -5
echo ""

# 4. Проверить JavaScript файлы
echo "📋 Проверка загрузки JavaScript:"
curl -s -k https://panel.anomaly-connect.online/ 2>/dev/null | grep -o 'src="[^"]*\.js[^"]*"' | head -5 || echo "  JS файлы не найдены в HTML"
echo ""

# 5. Проверить конфигурацию Nginx для панели
echo "📋 Проверка конфигурации Nginx:"
grep -A 10 "panel.anomaly-connect.online" nginx/conf.d/panel.conf | head -15
echo ""

echo "✅ Проверка завершена"
echo ""
echo "💡 Рекомендации:"
echo "   1. Попробуйте открыть: https://panel.anomaly-connect.online/dashboard/"
echo "   2. Откройте консоль браузера (F12) и проверьте ошибки JavaScript"
echo "   3. Очистите кэш браузера (Ctrl+Shift+Delete)"
echo "   4. Попробуйте в режиме инкогнито (Ctrl+Shift+N)"


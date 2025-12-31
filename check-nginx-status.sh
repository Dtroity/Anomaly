#!/bin/bash

# Скрипт для проверки статуса Nginx

set -e

echo "🔍 Проверка статуса Nginx"
echo "========================"
echo ""

cd /opt/Anomaly

# 1. Проверить конфигурацию
echo "📋 Проверка конфигурации Nginx:"
docker-compose exec nginx nginx -t
echo ""

# 2. Проверить статус контейнера
echo "📊 Статус контейнера:"
docker-compose ps nginx
echo ""

# 3. Проверить логи (последние 15 строк)
echo "📋 Логи Nginx (последние 15 строк):"
docker-compose logs --tail=15 nginx
echo ""

# 4. Проверить доступность сервисов
echo "🌐 Проверка доступности сервисов:"

# API
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.anomaly-connect.online/health 2>/dev/null)
if [ "$API_STATUS" = "200" ]; then
    echo "  ✅ API: https://api.anomaly-connect.online/health (HTTP $API_STATUS)"
else
    echo "  ❌ API: HTTP $API_STATUS"
fi

# Панель
PANEL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k https://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$PANEL_STATUS" = "200" ]; then
    echo "  ✅ Панель: https://panel.anomaly-connect.online (HTTP $PANEL_STATUS)"
else
    echo "  ❌ Панель: HTTP $PANEL_STATUS"
fi

# Главный домен
MAIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://anomaly-connect.online/ 2>/dev/null)
if [ "$MAIN_STATUS" = "200" ]; then
    echo "  ✅ Главный домен: https://anomaly-connect.online (HTTP $MAIN_STATUS)"
else
    echo "  ⚠️  Главный домен: HTTP $MAIN_STATUS"
fi

echo ""
echo "✅ Проверка завершена"


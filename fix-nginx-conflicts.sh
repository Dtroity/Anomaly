#!/bin/bash

# Скрипт для исправления конфликтов конфигурации Nginx

set -e

echo "🔧 Исправление конфликтов конфигурации Nginx"
echo "============================================="
echo ""

cd /opt/Anomaly

# 1. Переименовать неиспользуемые HTTP конфигурации
echo "📋 Переименование неиспользуемых HTTP конфигураций..."
if [ -f nginx/conf.d/default-http-only.conf ]; then
    mv nginx/conf.d/default-http-only.conf nginx/conf.d/default-http-only.conf.bak
    echo "✅ default-http-only.conf переименован в .bak"
fi

if [ -f nginx/conf.d/default-http.conf ]; then
    mv nginx/conf.d/default-http.conf nginx/conf.d/default-http.conf.bak
    echo "✅ default-http.conf переименован в .bak"
fi

# 2. Проверить конфигурацию Nginx
echo ""
echo "📋 Проверка конфигурации Nginx..."
docker-compose exec nginx nginx -t

# 3. Перезапустить Nginx
echo ""
echo "🔄 Перезапуск Nginx..."
docker-compose restart nginx

# 4. Проверить логи
echo ""
echo "📋 Логи Nginx (последние 10 строк):"
docker-compose logs --tail=10 nginx

echo ""
echo "✅ Готово!"


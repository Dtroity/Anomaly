#!/bin/bash

# Финальное исправление Nginx - удаление всех SSL конфигураций

set -e

echo "🔧 Финальное исправление Nginx..."
echo ""

# 1. Остановить Nginx
echo "⏸️  Остановка Nginx..."
docker-compose stop nginx

# 2. Удалить ВСЕ SSL конфигурации
echo "🧹 Удаление всех SSL конфигураций..."
cd nginx/conf.d

# Удалить все конфигурации
rm -f default.conf main.conf panel.conf default-ssl.conf.bak main-ssl.conf.bak panel-ssl.conf.bak 2>/dev/null || true

# Использовать только HTTP конфигурацию
if [ -f default-http-only.conf ]; then
    cp default-http-only.conf default.conf
    echo "✅ Использована HTTP конфигурация"
else
    echo "❌ Файл default-http-only.conf не найден!"
    exit 1
fi

# Убедиться, что других конфигураций нет
ls -la

cd ../..

# 3. Перезапустить Nginx
echo ""
echo "🚀 Перезапуск Nginx..."
docker-compose rm -f nginx
docker-compose up -d --no-deps nginx

# 4. Подождать
sleep 5

# 5. Проверить логи
echo ""
echo "📋 Логи Nginx (последние 20 строк):"
docker-compose logs --tail=20 nginx

# 6. Проверить статус
echo ""
echo "📊 Статус Nginx:"
docker-compose ps nginx

# 7. Проверить доступность
echo ""
echo "🌐 Проверка доступности:"
echo -n "Локальный API (через Nginx): "
curl -s http://localhost/health 2>/dev/null && echo "✅" || echo "❌"

echo -n "Внешний API: "
curl -s http://api.anomaly-connect.online/health 2>/dev/null && echo "✅" || echo "❌"

echo ""
echo "✅ Готово!"


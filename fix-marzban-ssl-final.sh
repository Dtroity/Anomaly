#!/bin/bash

# Финальное исправление SSL для Marzban

set -e

echo "🔐 Финальное исправление SSL для Marzban"
echo "========================================"
echo ""

cd /opt/Anomaly

# 1. Убедиться, что сертификаты в volume
echo "📋 Проверка сертификатов..."
if ! docker run --rm -v anomaly_marzban_data:/data alpine test -f /data/ssl/cert.pem; then
    echo "❌ Сертификаты не найдены в volume"
    echo "   Копирую сертификаты..."
    docker run --rm -v anomaly_marzban_data:/data alpine mkdir -p /data/ssl
    docker run --rm \
      -v anomaly_marzban_data:/data \
      -v "$(pwd)/nginx/ssl:/certs:ro" \
      alpine sh -c 'cp /certs/fullchain.pem /data/ssl/cert.pem && cp /certs/privkey.pem /data/ssl/key.pem && chmod 644 /data/ssl/cert.pem && chmod 600 /data/ssl/key.pem'
    echo "✅ Сертификаты скопированы"
else
    echo "✅ Сертификаты найдены в volume"
fi

# 2. Убедиться, что .env.marzban правильный
echo ""
echo "🔄 Проверка .env.marzban..."

# Удалить старые строки
sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.marzban
sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.marzban
sed -i '/^UVICORN_HOST=/d' .env.marzban

# Добавить правильные строки
echo "UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/cert.pem" >> .env.marzban
echo "UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem" >> .env.marzban
echo "UVICORN_HOST=0.0.0.0" >> .env.marzban

echo "✅ .env.marzban обновлен"

# 3. Проверить docker-compose.yml
echo ""
echo "🔄 Проверка docker-compose.yml..."

if ! grep -q "nginx/ssl:/var/lib/marzban/ssl" docker-compose.yml; then
    echo "⚠️  Монтирование SSL не найдено, добавляю..."
    # Это нужно сделать вручную или через sed
    echo "   ⚠️  Нужно вручную добавить в docker-compose.yml:"
    echo "      - ./nginx/ssl:/var/lib/marzban/ssl:ro"
    echo "   в volumes для marzban"
fi

# 4. Пересоздать контейнер (не просто перезапустить!)
echo ""
echo "🔄 Пересоздание контейнера Marzban..."
docker-compose stop marzban
docker-compose rm -f marzban
docker-compose up -d marzban

# 5. Подождать запуска
echo "⏳ Ожидание запуска Marzban (20 секунд)..."
sleep 20

# 6. Проверить переменные окружения
echo ""
echo "📋 Переменные окружения в контейнере:"
docker-compose exec marzban env | grep -E "UVICORN_SSL|UVICORN_HOST" || echo "⚠️  Переменные не найдены"

# 7. Проверить логи
echo ""
echo "📋 Логи Marzban (последние 20 строк):"
docker-compose logs --tail=20 marzban

# 8. Проверить привязку
echo ""
echo "🔍 Проверка привязки:"
if docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
    echo "✅ Marzban слушает на https://0.0.0.0:62050"
elif docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "⚠️  Marzban слушает на http://0.0.0.0:62050 (без SSL)"
else
    echo "❌ Marzban все еще слушает на 127.0.0.1:62050"
    echo ""
    echo "💡 Возможные причины:"
    echo "   1. Переменные окружения не применяются"
    echo "   2. Сертификаты не найдены в контейнере"
    echo "   3. Marzban требует другой формат путей"
fi

# 9. Проверить панель
echo ""
echo "🌐 Проверка панели:"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -k https://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✅ Панель доступна (HTTP $RESPONSE)"
elif [ "$RESPONSE" = "502" ]; then
    echo "❌ Bad Gateway (502)"
else
    echo "⚠️  HTTP $RESPONSE"
fi

echo ""
echo "✅ Готово!"


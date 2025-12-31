#!/bin/bash

# Исправление проблемы с сертификатами для Marzban
# Проблема: сертификаты в volume, но нужны в bind mount

set -e

echo "🔐 Исправление сертификатов для Marzban"
echo "========================================"
echo ""

cd /opt/Anomaly

# 1. Проверить, что сертификаты есть в nginx/ssl на хосте
echo "📋 Проверка сертификатов на хосте..."
if [ ! -f nginx/ssl/fullchain.pem ] || [ ! -f nginx/ssl/privkey.pem ]; then
    echo "❌ Сертификаты не найдены в nginx/ssl/"
    echo "   Проверяю, откуда их скопировать..."
    
    # Проверить, есть ли они в /etc/letsencrypt
    if [ -f /etc/letsencrypt/live/anomaly-connect.online/fullchain.pem ]; then
        echo "   Найдены в /etc/letsencrypt, копирую..."
        mkdir -p nginx/ssl
        cp /etc/letsencrypt/live/anomaly-connect.online/fullchain.pem nginx/ssl/fullchain.pem
        cp /etc/letsencrypt/live/anomaly-connect.online/privkey.pem nginx/ssl/privkey.pem
        chmod 644 nginx/ssl/fullchain.pem
        chmod 600 nginx/ssl/privkey.pem
        echo "✅ Сертификаты скопированы"
    else
        echo "❌ Сертификаты не найдены ни в nginx/ssl, ни в /etc/letsencrypt"
        echo "   Нужно сначала получить SSL сертификаты"
        exit 1
    fi
else
    echo "✅ Сертификаты найдены в nginx/ssl/"
fi

# 2. Проверить, что сертификаты доступны в контейнере
echo ""
echo "📋 Проверка сертификатов в контейнере Marzban..."
if docker-compose exec marzban test -f /var/lib/marzban/ssl/fullchain.pem 2>/dev/null; then
    echo "✅ Сертификаты доступны в контейнере"
else
    echo "❌ Сертификаты не доступны в контейнере"
    echo "   Проверяю монтирование..."
    docker-compose exec marzban ls -la /var/lib/marzban/ssl/ 2>/dev/null || echo "   Директория не существует"
fi

# 3. Обновить .env.marzban для использования правильных путей
echo ""
echo "🔄 Обновление .env.marzban..."

# Удалить старые строки
sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.marzban
sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.marzban
sed -i '/^UVICORN_HOST=/d' .env.marzban

# Использовать пути к сертификатам через bind mount
echo "UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/fullchain.pem" >> .env.marzban
echo "UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/privkey.pem" >> .env.marzban
echo "UVICORN_HOST=0.0.0.0" >> .env.marzban

echo "✅ .env.marzban обновлен"

# 4. Пересоздать контейнер
echo ""
echo "🔄 Пересоздание контейнера Marzban..."
docker-compose stop marzban
docker-compose rm -f marzban
docker-compose up -d marzban

# 5. Подождать запуска
echo "⏳ Ожидание запуска Marzban (20 секунд)..."
sleep 20

# 6. Проверить переменные и сертификаты
echo ""
echo "📋 Переменные окружения:"
docker-compose exec marzban env | grep -E "UVICORN_SSL|UVICORN_HOST" || echo "⚠️  Переменные не найдены"

echo ""
echo "📋 Сертификаты в контейнере:"
docker-compose exec marzban ls -la /var/lib/marzban/ssl/ 2>/dev/null || echo "❌ Директория не найдена"

# 7. Проверить логи
echo ""
echo "📋 Логи Marzban (последние 30 строк):"
docker-compose logs --tail=30 marzban

# 8. Проверить привязку
echo ""
echo "🔍 Проверка привязки:"
if docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
    echo "✅ Marzban слушает на https://0.0.0.0:62050"
elif docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "⚠️  Marzban слушает на http://0.0.0.0:62050 (без SSL)"
else
    echo "❌ Marzban все еще слушает на 127.0.0.1:62050"
fi

# 9. Проверить панель
echo ""
echo "🌐 Проверка панели:"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -k https://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✅ Панель доступна (HTTP $RESPONSE)"
else
    echo "❌ HTTP $RESPONSE"
fi

echo ""
echo "✅ Готово!"


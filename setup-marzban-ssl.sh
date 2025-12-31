#!/bin/bash

# Настройка SSL для Marzban, чтобы он мог слушать на 0.0.0.0

set -e

echo "🔐 Настройка SSL для Marzban"
echo "============================"
echo ""

PROJECT_DIR="/opt/Anomaly"
cd "$PROJECT_DIR"

# 1. Проверить наличие SSL сертификатов
CERT_PATH="/etc/letsencrypt/live/anomaly-connect.online"
if [ ! -d "$CERT_PATH" ]; then
    echo "❌ SSL сертификаты не найдены"
    exit 1
fi

echo "✅ SSL сертификаты найдены: $CERT_PATH"
echo ""

# 2. Создать директорию для сертификатов Marzban в volume
echo "📁 Настройка сертификатов для Marzban..."

# Проверить, что сертификаты существуют
if [ ! -f "$CERT_PATH/fullchain.pem" ] || [ ! -f "$CERT_PATH/privkey.pem" ]; then
    echo "❌ Сертификаты не найдены в $CERT_PATH"
    echo "   Проверьте путь к сертификатам"
    exit 1
fi

echo "✅ Сертификаты найдены:"
echo "   - $CERT_PATH/fullchain.pem"
echo "   - $CERT_PATH/privkey.pem"

# Создать директорию в volume
docker run --rm \
  -v anomaly_marzban_data:/data \
  alpine mkdir -p /data/ssl

# Копировать сертификаты в volume
echo "📋 Копирование сертификатов..."
docker run --rm \
  -v anomaly_marzban_data:/data \
  -v "$CERT_PATH:/certs:ro" \
  alpine sh -c 'if [ -f /certs/fullchain.pem ] && [ -f /certs/privkey.pem ]; then cp /certs/fullchain.pem /data/ssl/cert.pem && cp /certs/privkey.pem /data/ssl/key.pem && chmod 644 /data/ssl/cert.pem && chmod 600 /data/ssl/key.pem && echo "Сертификаты скопированы"; else echo "Ошибка: сертификаты не найдены в /certs"; exit 1; fi'

echo "✅ Сертификаты скопированы в volume Marzban"
echo ""

# 3. Обновить .env.marzban для использования SSL
echo "🔄 Обновление .env.marzban..."

if [ -f .env.marzban ]; then
    # Создать резервную копию
    cp .env.marzban .env.marzban.backup.$(date +%Y%m%d_%H%M%S)
    
    # Обновить UVICORN_SSL_CERTFILE и UVICORN_SSL_KEYFILE
    sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.marzban
    sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.marzban
    
    echo "UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/cert.pem" >> .env.marzban
    echo "UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem" >> .env.marzban
    
    # Убедиться, что UVICORN_HOST=0.0.0.0
    sed -i '/^UVICORN_HOST=/d' .env.marzban
    echo "UVICORN_HOST=0.0.0.0" >> .env.marzban
    
    echo "✅ .env.marzban обновлен"
else
    echo "❌ Файл .env.marzban не найден"
    exit 1
fi

# 4. Обновить docker-compose.yml для монтирования SSL сертификатов
echo ""
echo "🔄 Проверка docker-compose.yml..."

# Проверить, есть ли уже монтирование ssl
if ! grep -q "marzban_data:/var/lib/marzban/ssl" docker-compose.yml 2>/dev/null; then
    echo "⚠️  Нужно вручную добавить монтирование SSL в docker-compose.yml"
    echo "   Добавьте в volumes для marzban:"
    echo "   - ./nginx/ssl:/var/lib/marzban/ssl:ro"
fi

# 5. Перезапустить Marzban
echo ""
echo "🔄 Перезапуск Marzban..."
docker-compose stop marzban
docker-compose rm -f marzban
docker-compose up -d marzban

# Подождать запуска
echo "⏳ Ожидание запуска Marzban (15 секунд)..."
sleep 15

# 6. Проверить логи
echo ""
echo "📋 Логи Marzban (последние 20 строк):"
docker-compose logs --tail=20 marzban

# 7. Проверить привязку
echo ""
echo "🔍 Проверка привязки:"
if docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "✅ Marzban слушает на 0.0.0.0:62050"
elif docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
    echo "✅ Marzban слушает на https://0.0.0.0:62050 (SSL)"
else
    echo "⚠️  Не удалось определить адрес привязки"
fi

# 8. Проверить доступность панели
echo ""
echo "🌐 Проверка доступности панели:"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -k https://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✅ Панель доступна (HTTP $RESPONSE)"
elif [ "$RESPONSE" = "502" ]; then
    echo "❌ Bad Gateway (502)"
    echo ""
    echo "💡 Возможные решения:"
    echo "   1. Проверьте, что сертификаты правильно смонтированы"
    echo "   2. Проверьте логи Marzban на ошибки SSL"
    echo "   3. Попробуйте использовать host network mode (не рекомендуется)"
else
    echo "⚠️  HTTP $RESPONSE"
fi

echo ""
echo "✅ Готово!"


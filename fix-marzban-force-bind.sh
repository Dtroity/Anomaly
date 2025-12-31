#!/bin/bash

# Принудительное исправление привязки Marzban к 0.0.0.0

set -e

echo "🔧 Принудительное исправление привязки Marzban..."
echo ""

# 1. Проверить конфигурацию
echo "📋 Проверка .env.marzban:"
cat .env.marzban | grep -E "UVICORN_HOST|UVICORN_PORT" || echo "⚠️  Переменные не найдены"

echo ""

# 2. Убедиться, что UVICORN_HOST=0.0.0.0
echo "🔄 Установка UVICORN_HOST=0.0.0.0..."
sed -i '/^UVICORN_HOST=/d' .env.marzban
sed -i '/^UVICORN_PORT=/d' .env.marzban
echo "UVICORN_HOST=0.0.0.0" >> .env.marzban
echo "UVICORN_PORT=62050" >> .env.marzban

echo "✅ Конфигурация обновлена"
echo ""

# 3. Пересоздать контейнер Marzban (не просто перезапустить)
echo "🔄 Пересоздание контейнера Marzban..."
docker-compose stop marzban
docker-compose rm -f marzban
docker-compose up -d marzban

# 4. Подождать запуска
echo "⏳ Ожидание запуска Marzban (15 секунд)..."
sleep 15

# 5. Проверить логи
echo ""
echo "📋 Логи Marzban (последние 20 строк):"
docker-compose logs --tail=20 marzban

# 6. Проверить, на каком адресе слушает
echo ""
echo "🔍 Проверка привязки:"
if docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "✅ Marzban слушает на 0.0.0.0:62050"
elif docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on http://127.0.0.1:62050"; then
    echo "❌ Marzban все еще слушает на 127.0.0.1:62050"
    echo "⚠️  Возможно, Marzban игнорирует UVICORN_HOST без SSL сертификатов"
else
    echo "⚠️  Не удалось определить адрес привязки"
fi

# 7. Проверить доступность
echo ""
echo "🌐 Проверка доступности:"
echo -n "  Из контейнера Nginx: "
docker-compose exec -T nginx wget -qO- --timeout=5 http://marzban:62050/ 2>/dev/null | head -5 && echo "✅" || echo "❌"

echo -n "  Панель через Nginx: "
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✅ (HTTP $RESPONSE)"
elif [ "$RESPONSE" = "502" ]; then
    echo "❌ Bad Gateway (502)"
    echo ""
    echo "💡 Решение: Marzban может требовать SSL сертификаты для привязки к 0.0.0.0"
    echo "   Попробуйте получить SSL сертификаты: ./setup-ssl.sh"
else
    echo "⚠️  HTTP $RESPONSE"
fi

echo ""
echo "✅ Готово!"


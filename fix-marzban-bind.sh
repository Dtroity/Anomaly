#!/bin/bash

# Исправление проблемы с привязкой Marzban к 0.0.0.0

set -e

echo "🔧 Исправление привязки Marzban к 0.0.0.0..."
echo ""

# 1. Проверить текущую конфигурацию
echo "📋 Текущая конфигурация Marzban:"
if [ -f .env.marzban ]; then
    grep -E "UVICORN_HOST|UVICORN_PORT" .env.marzban || echo "⚠️  UVICORN_HOST не найден"
else
    echo "❌ Файл .env.marzban не найден"
    exit 1
fi

echo ""

# 2. Обновить конфигурацию
echo "🔄 Обновление конфигурации..."

# Создать резервную копию
cp .env.marzban .env.marzban.backup

# Убедиться, что UVICORN_HOST=0.0.0.0
if ! grep -q "^UVICORN_HOST=0.0.0.0" .env.marzban; then
    # Удалить старую строку если есть
    sed -i '/^UVICORN_HOST=/d' .env.marzban
    
    # Добавить правильную строку
    echo "UVICORN_HOST=0.0.0.0" >> .env.marzban
    echo "✅ UVICORN_HOST установлен в 0.0.0.0"
else
    echo "✅ UVICORN_HOST уже установлен в 0.0.0.0"
fi

# Убедиться, что UVICORN_PORT=62050
if ! grep -q "^UVICORN_PORT=62050" .env.marzban; then
    sed -i '/^UVICORN_PORT=/d' .env.marzban
    echo "UVICORN_PORT=62050" >> .env.marzban
    echo "✅ UVICORN_PORT установлен в 62050"
else
    echo "✅ UVICORN_PORT уже установлен в 62050"
fi

echo ""

# 3. Перезапустить Marzban
echo "🔄 Перезапуск Marzban..."
docker-compose restart marzban

# Подождать запуска
echo "⏳ Ожидание запуска Marzban..."
sleep 10

# 4. Проверить логи
echo ""
echo "📋 Логи Marzban (последние 15 строк):"
docker-compose logs --tail=15 marzban | grep -E "Uvicorn running|INFO|ERROR" || docker-compose logs --tail=15 marzban

# 5. Проверить доступность
echo ""
echo "🌐 Проверка доступности Marzban:"
echo -n "  Из контейнера Nginx: "
docker-compose exec -T nginx wget -qO- --timeout=5 http://marzban:62050/ 2>/dev/null | head -5 && echo "✅" || echo "❌"

echo -n "  Панель через Nginx: "
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✅ (HTTP $RESPONSE)"
elif [ "$RESPONSE" = "502" ]; then
    echo "❌ Bad Gateway (502)"
else
    echo "⚠️  HTTP $RESPONSE"
fi

echo ""
echo "✅ Готово!"


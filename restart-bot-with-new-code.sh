#!/bin/bash

# Скрипт для безопасного перезапуска бота с новым кодом

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔄 Перезапуск бота с новым кодом"
echo "================================"
echo ""

# 1. Обновить код
echo "📥 Обновление кода..."
git pull

# 2. Остановить бота
echo "⏸️  Остановка бота..."
docker-compose stop bot 2>/dev/null || docker stop anomaly-bot 2>/dev/null

# 3. Удалить старый контейнер
echo "🗑️  Удаление старого контейнера..."
docker-compose rm -f bot 2>/dev/null || docker rm -f anomaly-bot 2>/dev/null

# 4. Пересобрать и запустить бота (без зависимостей, чтобы избежать ошибки ContainerConfig)
echo "🔨 Пересборка и запуск бота..."
docker-compose up -d --build --no-deps bot

# 5. Подождать немного
echo "⏳ Ожидание запуска..."
sleep 10

# 6. Проверить статус
echo "📊 Статус бота:"
docker-compose ps bot || docker ps | grep anomaly-bot

echo ""
echo "📋 Логи бота (последние 20 строк):"
docker-compose logs --tail=20 bot 2>/dev/null || docker logs --tail=20 anomaly-bot

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Проверьте логи на ошибки:"
echo "   docker-compose logs --tail=50 bot | grep -i error"
echo ""


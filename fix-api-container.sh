#!/bin/bash
# Fix API container ContainerConfig error

echo "🔧 Исправление ошибки ContainerConfig для API контейнера"
echo "=================================================="

cd /opt/Anomaly || exit 1

echo "⏸️  Остановка всех сервисов..."
docker-compose stop

echo "🗑️  Удаление поврежденного API контейнера..."
docker rm -f anomaly-api 2>/dev/null || true
docker rm -f a896d15e023a_anomaly-api 2>/dev/null || true

echo "🧹 Очистка неиспользуемых контейнеров..."
docker container prune -f

echo "🚀 Запуск сервисов..."
docker-compose up -d

echo "✅ Готово!"
echo "💡 Проверьте статус: docker-compose ps"


#!/bin/bash

# Проверка и исправление SSL для Marzban

set -e

echo "🔍 Проверка SSL для Marzban"
echo "==========================="
echo ""

cd /opt/Anomaly

# 1. Проверить, что сертификаты скопированы в volume
echo "📋 Проверка сертификатов в volume:"
docker run --rm -v anomaly_marzban_data:/data alpine ls -la /data/ssl/ 2>/dev/null || echo "❌ Директория ssl не найдена"

echo ""

# 2. Проверить .env.marzban
echo "📋 Проверка .env.marzban:"
grep -E "UVICORN_SSL|UVICORN_HOST" .env.marzban || echo "⚠️  Переменные не найдены"

echo ""

# 3. Проверить docker-compose.yml
echo "📋 Проверка docker-compose.yml:"
grep -A 5 "marzban:" docker-compose.yml | grep -E "volumes|ssl" || echo "⚠️  Монтирование ssl не найдено"

echo ""

# 4. Проверить логи Marzban
echo "📋 Логи Marzban (последние 30 строк):"
docker-compose logs --tail=30 marzban | grep -E "Uvicorn running|SSL|ERROR|WARNING" || docker-compose logs --tail=30 marzban

echo ""

# 5. Проверить переменные окружения в контейнере
echo "📋 Переменные окружения в контейнере:"
docker-compose exec marzban env | grep -E "UVICORN_SSL|UVICORN_HOST" || echo "⚠️  Переменные не найдены в контейнере"

echo ""

# 6. Проверить наличие сертификатов в контейнере
echo "📋 Проверка сертификатов в контейнере:"
docker-compose exec marzban ls -la /var/lib/marzban/ssl/ 2>/dev/null || echo "❌ Сертификаты не найдены в контейнере"

echo ""
echo "✅ Проверка завершена"


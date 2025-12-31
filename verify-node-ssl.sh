#!/bin/bash

# Скрипт для проверки SSL на ноде

set -e

echo "🔍 Проверка SSL на ноде"
echo "======================="
echo ""

cd /opt/Anomaly

# 1. Проверить наличие сертификатов
echo "📋 Проверка сертификатов:"
if [ -f node-certs/certificate.pem ] && [ -f node-certs/key.pem ]; then
    echo "  ✅ Сертификаты найдены на хосте"
    ls -lh node-certs/
else
    echo "  ❌ Сертификаты не найдены"
    exit 1
fi
echo ""

# 2. Проверить сертификаты в контейнере
echo "📋 Проверка сертификатов в контейнере:"
if docker-compose -f docker-compose.node.yml exec -T marzban-node test -f /var/lib/marzban/ssl/certificate.pem 2>/dev/null; then
    echo "  ✅ Сертификаты доступны в контейнере"
    docker-compose -f docker-compose.node.yml exec marzban-node ls -lh /var/lib/marzban/ssl/
else
    echo "  ❌ Сертификаты не доступны в контейнере"
    echo "  Проверьте монтирование volume в docker-compose.node.yml"
fi
echo ""

# 3. Проверить .env.node
echo "📋 Проверка .env.node:"
grep -E "UVICORN_SSL|UVICORN_HOST" .env.node | grep -v "^#" || echo "  Параметры не найдены"
echo ""

# 4. Проверить логи
echo "📋 Логи ноды (последние 30 строк):"
docker-compose -f docker-compose.node.yml logs --tail=30 marzban-node
echo ""

# 5. Проверить привязку
echo "🔍 Проверка привязки:"
if docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
    echo "  ✅ Нода слушает на https://0.0.0.0:62050"
elif docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "  ⚠️  Нода слушает на http://0.0.0.0:62050 (без SSL)"
elif docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on http://127.0.0.1:62050"; then
    echo "  ❌ Нода все еще слушает на 127.0.0.1:62050"
    echo "  Возможные причины:"
    echo "    - Сертификаты не найдены в контейнере"
    echo "    - Неправильные пути в .env.node"
    echo "    - Нужно пересоздать контейнер"
else
    echo "  ⚠️  Не удалось определить привязку"
fi
echo ""

# 6. Проверить порты
echo "🔍 Проверка портов:"
docker-compose -f docker-compose.node.yml ps marzban-node | grep -o "0.0.0.0:[0-9]*->[0-9]*" || echo "  Порты не найдены"
echo ""

echo "✅ Проверка завершена"


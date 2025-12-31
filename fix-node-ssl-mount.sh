#!/bin/bash

# Скрипт для исправления монтирования SSL сертификатов на ноде

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление SSL на ноде"
echo "=========================="
echo ""

# 1. Проверить наличие сертификатов
echo "📋 Проверка сертификатов на хосте:"
if [ ! -f node-certs/certificate.pem ] || [ ! -f node-certs/key.pem ]; then
    echo "❌ Сертификаты не найдены в node-certs/"
    echo "   Создайте файлы certificate.pem и key.pem"
    exit 1
fi
echo "✅ Сертификаты найдены"
echo ""

# 2. Проверить формат сертификатов
echo "📋 Проверка формата сертификатов:"
if head -n 1 node-certs/certificate.pem | grep -q "BEGIN CERTIFICATE"; then
    echo "  ✅ certificate.pem имеет правильный формат"
else
    echo "  ❌ certificate.pem имеет неправильный формат"
    echo "  Ожидается: -----BEGIN CERTIFICATE-----"
    exit 1
fi

if head -n 1 node-certs/key.pem | grep -q "BEGIN.*PRIVATE KEY"; then
    echo "  ✅ key.pem имеет правильный формат"
else
    echo "  ❌ key.pem имеет неправильный формат"
    echo "  Ожидается: -----BEGIN PRIVATE KEY----- или -----BEGIN RSA PRIVATE KEY-----"
    exit 1
fi
echo ""

# 3. Проверить права доступа
echo "🔒 Установка прав доступа:"
chmod 644 node-certs/certificate.pem
chmod 600 node-certs/key.pem
echo "✅ Права установлены"
echo ""

# 4. Проверить docker-compose.node.yml
echo "📋 Проверка docker-compose.node.yml:"
if ! grep -q "node-certs:/var/lib/marzban/ssl:ro" docker-compose.node.yml; then
    echo "⚠️  Монтирование отсутствует, добавляю..."
    sed -i '/node_xray:\/usr\/local\/share\/xray/a\      - .\/node-certs:\/var\/lib\/marzban\/ssl:ro' docker-compose.node.yml
    echo "✅ Монтирование добавлено"
else
    echo "✅ Монтирование присутствует"
fi
echo ""

# 5. Пересоздать контейнер
echo "🔄 Пересоздание контейнера ноды..."
docker-compose -f docker-compose.node.yml down || true
docker-compose -f docker-compose.node.yml up -d marzban-node
echo "⏳ Ожидание запуска (20 секунд)..."
sleep 20
echo ""

# 6. Проверить доступность сертификатов в контейнере
echo "📋 Проверка сертификатов в контейнере:"
if docker-compose -f docker-compose.node.yml exec -T marzban-node test -f /var/lib/marzban/ssl/certificate.pem 2>/dev/null; then
    echo "  ✅ certificate.pem доступен"
    docker-compose -f docker-compose.node.yml exec marzban-node ls -lh /var/lib/marzban/ssl/certificate.pem
else
    echo "  ❌ certificate.pem НЕ доступен в контейнере"
    echo "  Проверьте монтирование volume"
fi

if docker-compose -f docker-compose.node.yml exec -T marzban-node test -f /var/lib/marzban/ssl/key.pem 2>/dev/null; then
    echo "  ✅ key.pem доступен"
    docker-compose -f docker-compose.node.yml exec marzban-node ls -lh /var/lib/marzban/ssl/key.pem
else
    echo "  ❌ key.pem НЕ доступен в контейнере"
fi
echo ""

# 7. Проверить переменные окружения
echo "📋 Переменные окружения в контейнере:"
docker-compose -f docker-compose.node.yml exec marzban-node env | grep -E "UVICORN_SSL|UVICORN_HOST" || true
echo ""

# 8. Проверить логи
echo "📋 Логи ноды (последние 30 строк):"
docker-compose -f docker-compose.node.yml logs --tail=30 marzban-node
echo ""

# 9. Проверить привязку
echo "🔍 Проверка привязки:"
if docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
    echo "  ✅ Нода слушает на https://0.0.0.0:62050"
elif docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "  ⚠️  Нода слушает на http://0.0.0.0:62050 (без SSL)"
else
    echo "  ❌ Нода не запустилась или слушает на 127.0.0.1"
fi
echo ""

echo "✅ Проверка завершена"
echo ""
echo "💡 Если сертификаты все еще не доступны:"
echo "   1. Убедитесь, что директория node-certs/ существует"
echo "   2. Проверьте, что файлы certificate.pem и key.pem содержат правильный PEM формат"
echo "   3. Попробуйте пересоздать контейнер: docker-compose -f docker-compose.node.yml up -d --force-recreate marzban-node"


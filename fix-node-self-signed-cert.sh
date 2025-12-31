#!/bin/bash

# Скрипт для настройки самоподписанного сертификата на ноде
# Устанавливает UVICORN_SSL_CA_TYPE=private для разрешения самоподписанных сертификатов

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Настройка самоподписанного сертификата на ноде"
echo "=================================================="
echo ""

# 1. Проверить наличие сертификатов
if [ ! -f node-certs/certificate.pem ] || [ ! -f node-certs/key.pem ]; then
    echo "❌ Сертификаты не найдены в node-certs/"
    echo "   Сначала запустите: ./generate-node-self-signed-cert.sh"
    exit 1
fi
echo "✅ Сертификаты найдены"
echo ""

# 2. Обновить .env.node
echo "🔄 Обновление .env.node..."

# Удалить старые записи
sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.node
sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.node
sed -i '/^UVICORN_SSL_CA_TYPE=/d' .env.node
sed -i '/^UVICORN_HOST=/d' .env.node

# Добавить новые записи
echo "UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/certificate.pem" >> .env.node
echo "UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem" >> .env.node
echo "UVICORN_SSL_CA_TYPE=private" >> .env.node
echo "UVICORN_HOST=0.0.0.0" >> .env.node

echo "✅ .env.node обновлен:"
grep -E "UVICORN_SSL|UVICORN_HOST" .env.node
echo ""

# 3. Пересоздать контейнер
echo "🔄 Пересоздание контейнера ноды..."
docker-compose -f docker-compose.node.yml down || true
docker-compose -f docker-compose.node.yml up -d marzban-node
echo "⏳ Ожидание запуска ноды (20 секунд)..."
sleep 20
echo ""

# 4. Проверить логи
echo "📋 Логи ноды (последние 30 строк):"
docker-compose -f docker-compose.node.yml logs --tail=30 marzban-node | grep -E "Uvicorn running|IMPORTANT|Error|Traceback" || true
echo ""

# 5. Проверить привязку
echo "🔍 Проверка привязки:"
if docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
    echo "  ✅ Нода слушает на https://0.0.0.0:62050"
    echo ""
    echo "✅ Готово! Нода должна быть доступна для Control Server."
    echo ""
    echo "📝 Следующие шаги:"
    echo "   1. Откройте панель Marzban на Control Server"
    echo "   2. Найдите вашу ноду (Node 1)"
    echo "   3. Нажмите кнопку 'Переподключиться' (Reconnect)"
    echo "   4. Ошибка '[Errno 111] Connection refused' должна исчезнуть"
elif docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "  ⚠️  Нода слушает на http://0.0.0.0:62050 (без SSL)"
    echo "  Проверьте логи выше для ошибок"
else
    echo "  ❌ Нода не запустилась или слушает на 127.0.0.1"
    echo "  Проверьте логи выше для ошибок"
fi
echo ""


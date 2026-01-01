#!/bin/bash

# Скрипт для исправления SSL конфигурации ноды для приема подключений от Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление SSL конфигурации ноды для Marzban"
echo "================================================"
echo ""

# 1. Проверить текущую конфигурацию
echo "📋 Текущая конфигурация .env.node:"
if [ -f .env.node ]; then
    echo "  UVICORN_SSL_CERTFILE:"
    grep UVICORN_SSL_CERTFILE .env.node || echo "    ⚠️  Не установлен"
    echo "  UVICORN_SSL_KEYFILE:"
    grep UVICORN_SSL_KEYFILE .env.node || echo "    ⚠️  Не установлен"
    echo "  UVICORN_SSL_CA_TYPE:"
    grep UVICORN_SSL_CA_TYPE .env.node || echo "    ⚠️  Не установлен"
else
    echo "  ⚠️  Файл .env.node не найден"
fi
echo ""

# 2. Проверить сертификат
echo "🔍 Проверка сертификата:"
CERT_PATH="/var/lib/marzban-node/ssl/certificate.pem"
if [ -f "$CERT_PATH" ]; then
    echo "  ✅ Сертификат найден: $CERT_PATH"
    CERT_INFO=$(openssl x509 -in "$CERT_PATH" -noout -text 2>/dev/null | grep -E "Subject:|Issuer:" | head -2)
    if [ -n "$CERT_INFO" ]; then
        echo "  📋 Информация о сертификате:"
        echo "$CERT_INFO" | sed 's/^/    /'
    fi
else
    echo "  ❌ Сертификат не найден: $CERT_PATH"
    echo "  💡 Скачайте сертификат из панели Marzban"
    exit 1
fi
echo ""

# 3. Проверить, есть ли приватный ключ
echo "🔍 Поиск приватного ключа:"
KEY_PATHS=(
    "/var/lib/marzban-node/ssl/key.pem"
    "/var/lib/marzban-node/ssl/private_key.pem"
    "./node-certs/key.pem"
    "./node-certs/private_key.pem"
)

FOUND_KEY=""
for key_path in "${KEY_PATHS[@]}"; do
    if [ -f "$key_path" ]; then
        echo "  ✅ Найден ключ: $key_path"
        FOUND_KEY="$key_path"
        break
    fi
done

if [ -z "$FOUND_KEY" ]; then
    echo "  ⚠️  Приватный ключ не найден"
    echo "  💡 Возможно, сертификат из панели содержит только публичную часть"
    echo "  💡 Нода может использовать самоподписанный сертификат для сервера"
fi
echo ""

# 4. Обновить .env.node для использования сертификата
echo "🔄 Обновление .env.node..."

# Создать backup
if [ -f .env.node ]; then
    cp .env.node .env.node.backup.$(date +%Y%m%d_%H%M%S)
fi

# Если ключ найден, использовать его, иначе оставить пустым (нода сгенерирует свой)
if [ -n "$FOUND_KEY" ]; then
    CERT_FILE="/var/lib/marzban-node/ssl/certificate.pem"
    KEY_FILE="$FOUND_KEY"
    
    # Обновить UVICORN_SSL_CERTFILE и UVICORN_SSL_KEYFILE
    sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.node
    sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.node
    sed -i '/^UVICORN_SSL_CA_TYPE=/d' .env.node
    
    echo "UVICORN_SSL_CERTFILE=$CERT_FILE" >> .env.node
    echo "UVICORN_SSL_KEYFILE=$KEY_FILE" >> .env.node
    echo "UVICORN_SSL_CA_TYPE=private" >> .env.node
    
    echo "  ✅ Настроен сертификат и ключ для сервера"
else
    # Если ключа нет, настроить только для приема клиентских сертификатов
    sed -i '/^UVICORN_SSL_CA_TYPE=/d' .env.node
    echo "UVICORN_SSL_CA_TYPE=private" >> .env.node
    echo "  ✅ Настроен для приема клиентских сертификатов (самоподписанный серверный сертификат)"
fi

echo ""

# 5. Показать обновленную конфигурацию
echo "📋 Обновленная конфигурация:"
grep -E "UVICORN_SSL|SSL_CLIENT_CERT_FILE|CONTROL_SERVER_URL" .env.node
echo ""

# 6. Перезапустить marzban-node
echo "🔄 Перезапуск marzban-node..."
if docker ps | grep -q anomaly-node; then
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart anomaly-node 2>/dev/null || \
    echo "  ⚠️  Не удалось перезапустить автоматически"
else
    echo "  ⚠️  marzban-node не запущен"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Проверьте логи: docker logs anomaly-node --tail=30"
echo "   3. Вернитесь в панель Marzban и нажмите 'Переподключиться'"
echo ""


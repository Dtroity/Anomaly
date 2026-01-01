#!/bin/bash

# Скрипт для исправления пути к ключу в .env.node

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление пути к ключу в .env.node"
echo "========================================"
echo ""

# 1. Проверить текущий путь
echo "📋 Текущий путь к ключу:"
CURRENT_KEY=$(grep "^UVICORN_SSL_KEYFILE=" .env.node | cut -d'=' -f2)
echo "  $CURRENT_KEY"
echo ""

# 2. Найти ключ
echo "🔍 Поиск ключа..."
KEY_PATHS=(
    "./node-certs/key.pem"
    "/var/lib/marzban-node/ssl/key.pem"
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
    echo "  ❌ Ключ не найден"
    echo "  💡 Нода будет использовать самоподписанный сертификат"
    # Удалить UVICORN_SSL_KEYFILE, чтобы нода сгенерировала свой ключ
    sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.node
    sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.node
    echo "  ✅ Удалены пути к сертификату и ключу - нода сгенерирует свои"
else
    # Использовать путь внутри контейнера
    if [[ "$FOUND_KEY" == "./node-certs/"* ]]; then
        # Преобразовать ./node-certs/key.pem в /var/lib/marzban-node/node-certs/key.pem
        KEY_NAME=$(basename "$FOUND_KEY")
        NEW_KEY_PATH="/var/lib/marzban-node/node-certs/$KEY_NAME"
    else
        NEW_KEY_PATH="$FOUND_KEY"
    fi
    
    # Обновить .env.node
    sed -i "s|^UVICORN_SSL_KEYFILE=.*|UVICORN_SSL_KEYFILE=$NEW_KEY_PATH|" .env.node
    
    # Также обновить путь к сертификату, если нужно
    CERT_PATH="/var/lib/marzban-node/ssl/certificate.pem"
    sed -i "s|^UVICORN_SSL_CERTFILE=.*|UVICORN_SSL_CERTFILE=$CERT_PATH|" .env.node
    
    echo "  ✅ Путь к ключу обновлен: $NEW_KEY_PATH"
fi

echo ""

# 3. Показать обновленную конфигурацию
echo "📋 Обновленная конфигурация:"
grep -E "UVICORN_SSL|SSL_CLIENT_CERT_FILE" .env.node
echo ""

# 4. Перезапустить marzban-node
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


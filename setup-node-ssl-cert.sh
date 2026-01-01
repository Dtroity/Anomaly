#!/bin/bash

# Скрипт для настройки SSL сертификата на ноде

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Настройка SSL сертификата на ноде"
echo "====================================="
echo ""

# 1. Проверить текущий .env.node
echo "📋 Текущая конфигурация .env.node:"
if [ -f .env.node ]; then
    echo "  SSL_CLIENT_CERT_FILE:"
    grep SSL_CLIENT_CERT_FILE .env.node || echo "    ⚠️  Не установлен"
    echo "  CONTROL_SERVER_URL:"
    grep CONTROL_SERVER_URL .env.node || echo "    ⚠️  Не установлен"
    echo "  SERVICE_PROTOCOL:"
    grep SERVICE_PROTOCOL .env.node || echo "    ⚠️  Не установлен"
else
    echo "  ⚠️  Файл .env.node не найден"
fi
echo ""

# 2. Проверить наличие сертификата
echo "🔍 Поиск сертификата..."
CERT_PATHS=(
    "/var/lib/marzban-node/ssl/certificate.pem"
    "/var/lib/marzban-node/ssl_client_cert.pem"
    "./node-certs/certificate.pem"
    "./certificate.pem"
)

FOUND_CERT=""
for cert_path in "${CERT_PATHS[@]}"; do
    if [ -f "$cert_path" ]; then
        echo "  ✅ Найден сертификат: $cert_path"
        FOUND_CERT="$cert_path"
        break
    fi
done

if [ -z "$FOUND_CERT" ]; then
    echo "  ❌ Сертификат не найден"
    echo ""
    echo "  💡 Инструкции:"
    echo "     1. Откройте панель Marzban: https://panel.anomaly-connect.online"
    echo "     2. Перейдите в 'Marzban-Node'"
    echo "     3. Нажмите 'Скачать сертификат' для Node 1"
    echo "     4. Сохраните сертификат на ноде"
    echo "     5. Запустите этот скрипт снова"
    exit 1
fi

echo ""

# 3. Создать директорию для сертификата, если нужно
CERT_DIR="/var/lib/marzban-node/ssl"
if [ ! -d "$CERT_DIR" ]; then
    echo "📁 Создание директории для сертификата..."
    mkdir -p "$CERT_DIR"
    echo "  ✅ Директория создана: $CERT_DIR"
fi

# 4. Скопировать сертификат в правильное место
if [ "$FOUND_CERT" != "/var/lib/marzban-node/ssl/certificate.pem" ]; then
    echo "📋 Копирование сертификата..."
    cp "$FOUND_CERT" "/var/lib/marzban-node/ssl/certificate.pem"
    chmod 644 "/var/lib/marzban-node/ssl/certificate.pem"
    echo "  ✅ Сертификат скопирован в: /var/lib/marzban-node/ssl/certificate.pem"
fi

# 5. Обновить .env.node
echo ""
echo "🔄 Обновление .env.node..."

# Создать backup
if [ -f .env.node ]; then
    cp .env.node .env.node.backup.$(date +%Y%m%d_%H%M%S)
fi

# Добавить или обновить SSL_CLIENT_CERT_FILE
if [ -f .env.node ]; then
    # Удалить старую строку
    sed -i '/^SSL_CLIENT_CERT_FILE=/d' .env.node
fi

# Добавить новую строку
echo "SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem" >> .env.node

# Убедиться, что SERVICE_PROTOCOL установлен
if ! grep -q "^SERVICE_PROTOCOL=" .env.node 2>/dev/null; then
    echo "SERVICE_PROTOCOL=rest" >> .env.node
fi

echo "  ✅ .env.node обновлен"
echo ""

# 6. Показать обновленную конфигурацию
echo "📋 Обновленная конфигурация:"
grep -E "SSL_CLIENT_CERT_FILE|CONTROL_SERVER_URL|SERVICE_PROTOCOL" .env.node
echo ""

# 7. Перезапустить marzban-node
echo "🔄 Перезапуск marzban-node..."
if docker ps | grep -q anomaly-node; then
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart anomaly-node 2>/dev/null || \
    echo "  ⚠️  Не удалось перезапустить автоматически"
    echo "  💡 Перезапустите вручную: docker-compose -f docker-compose.node.yml restart marzban-node"
else
    echo "  ⚠️  marzban-node не запущен"
    echo "  💡 Запустите: docker-compose -f docker-compose.node.yml up -d"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Проверьте логи: docker logs anomaly-node --tail=50"
echo "   3. Вернитесь в панель Marzban и нажмите 'Переподключиться'"
echo ""


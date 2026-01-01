#!/bin/bash

# Скрипт для установки сертификата на ноде
# Использование: ./install-node-cert.sh <путь_к_сертификату>

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [ $# -eq 0 ]; then
    echo "❌ Укажите путь к сертификату"
    echo "Использование: $0 <путь_к_сертификату>"
    exit 1
fi

CERT_FILE="$1"

if [ ! -f "$CERT_FILE" ]; then
    echo "❌ Файл не найден: $CERT_FILE"
    exit 1
fi

echo "🔧 Установка сертификата на ноде"
echo "================================="
echo ""

# Проверить, что это валидный PEM сертификат
if ! grep -q "BEGIN CERTIFICATE" "$CERT_FILE"; then
    echo "  ⚠️  Предупреждение: файл не содержит 'BEGIN CERTIFICATE'"
    read -p "  Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Создать директорию для сертификатов
echo "📁 Создание директории для сертификатов..."
mkdir -p node-certs
mkdir -p /var/lib/marzban-node/ssl

# Скопировать сертификат
echo "📋 Копирование сертификата..."
cp "$CERT_FILE" /var/lib/marzban-node/ssl/certificate.pem
cp "$CERT_FILE" node-certs/certificate.pem
chmod 644 /var/lib/marzban-node/ssl/certificate.pem
chmod 644 node-certs/certificate.pem

echo "  ✅ Сертификат скопирован в:"
echo "     - /var/lib/marzban-node/ssl/certificate.pem"
echo "     - node-certs/certificate.pem"
echo ""

# Проверить, что SSL_CLIENT_CERT_FILE указывает на правильный путь
if [ -f .env.node ]; then
    echo "📋 Проверка .env.node..."
    CURRENT_CERT=$(grep "^SSL_CLIENT_CERT_FILE=" .env.node | cut -d'=' -f2)
    EXPECTED_CERT="/var/lib/marzban-node/ssl/certificate.pem"
    
    if [ "$CURRENT_CERT" != "$EXPECTED_CERT" ]; then
        echo "  ⚠️  SSL_CLIENT_CERT_FILE указывает на: $CURRENT_CERT"
        echo "  💡 Обновление на: $EXPECTED_CERT"
        sed -i "s|^SSL_CLIENT_CERT_FILE=.*|SSL_CLIENT_CERT_FILE=$EXPECTED_CERT|" .env.node
        echo "  ✅ Обновлено"
    else
        echo "  ✅ SSL_CLIENT_CERT_FILE уже правильный"
    fi
    echo ""
fi

# Проверить, что сертификат доступен в контейнере
if docker ps | grep -q anomaly-node; then
    echo "🔍 Проверка доступности сертификата в контейнере..."
    if docker exec anomaly-node test -f /var/lib/marzban-node/ssl/certificate.pem; then
        echo "  ✅ Сертификат доступен в контейнере"
    else
        echo "  ⚠️  Сертификат не найден в контейнере"
        echo "  💡 Нужно пересоздать контейнер или проверить volume mount"
    fi
    echo ""
    
    # Перезапустить ноду
    echo "🔄 Перезапуск ноды..."
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart anomaly-node 2>/dev/null || \
    echo "  ⚠️  Не удалось перезапустить автоматически"
    echo ""
fi

echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Проверьте логи: docker logs anomaly-node --tail=30"
echo "   3. Вернитесь в панель Marzban и нажмите 'Переподключиться'"
echo ""


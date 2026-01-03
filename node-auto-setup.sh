#!/bin/bash
# Автоматическая установка и настройка Marzban Node
# Этот скрипт выполняется на ноде (VPS #2) для автоматической настройки

set -e

echo "🚀 Автоматическая установка Marzban Node"
echo "========================================="
echo ""

# Параметры из переменных окружения
NODE_IP="${NODE_IP:-$(hostname -I | awk '{print $1}')}"
CONTROL_SERVER_URL="${CONTROL_SERVER_URL:-https://panel.anomaly-connect.online}"
NODE_PORT="${NODE_PORT:-62050}"
API_PORT="${API_PORT:-62051}"
CERTIFICATE="${CERTIFICATE:-}"

echo "📋 Параметры установки:"
echo "   NODE_IP: $NODE_IP"
echo "   CONTROL_SERVER_URL: $CONTROL_SERVER_URL"
echo "   NODE_PORT: $NODE_PORT"
echo "   API_PORT: $API_PORT"
echo ""

# 1. Проверка и установка зависимостей
echo "1️⃣  Проверка зависимостей..."
if ! command -v docker &> /dev/null; then
    echo "   📦 Установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

if ! command -v docker-compose &> /dev/null; then
    echo "   📦 Установка Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

echo "   ✅ Зависимости установлены"

# 2. Создание директорий
echo ""
echo "2️⃣  Создание директорий..."
mkdir -p /opt/Anomaly
mkdir -p /var/lib/marzban-node/ssl
mkdir -p /opt/Anomaly/node-certs
mkdir -p /opt/Anomaly/node-data

echo "   ✅ Директории созданы"

# 3. Клонирование репозитория (если еще не клонирован)
echo ""
echo "3️⃣  Проверка репозитория..."
if [ ! -d "/opt/Anomaly/.git" ]; then
    echo "   📥 Клонирование репозитория..."
    cd /opt
    git clone https://github.com/Dtroity/Anomaly.git || echo "   ⚠️  Репозиторий уже существует или ошибка клонирования"
fi

cd /opt/Anomaly
git pull || echo "   ⚠️  Ошибка обновления репозитория"

echo "   ✅ Репозиторий готов"

# 4. Установка сертификата
echo ""
echo "4️⃣  Установка сертификата..."
if [ -n "$CERTIFICATE" ]; then
    echo "$CERTIFICATE" > /var/lib/marzban-node/ssl/certificate.pem
    echo "$CERTIFICATE" > /opt/Anomaly/node-certs/certificate.pem
    echo "   ✅ Сертификат установлен"
else
    echo "   ⚠️  Сертификат не предоставлен, будет установлен позже"
fi

# 5. Создание/обновление .env.node
echo ""
echo "5️⃣  Настройка .env.node..."
cat > /opt/Anomaly/.env.node <<EOF
# Marzban Node Configuration
CONTROL_SERVER_URL=$CONTROL_SERVER_URL
NODE_PORT=$NODE_PORT
API_PORT=$API_PORT
SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem
EOF

echo "   ✅ .env.node настроен"

# 6. Генерация сертификата и ключа для сервера (если не существует)
echo ""
echo "6️⃣  Проверка серверного сертификата..."
if [ ! -f "/opt/Anomaly/node-certs/certificate.pem" ] || [ ! -f "/opt/Anomaly/node-certs/key.pem" ]; then
    echo "   🔐 Генерация самоподписанного сертификата для сервера..."
    mkdir -p /opt/Anomaly/node-certs
    openssl req -x509 -newkey rsa:4096 -keyout /opt/Anomaly/node-certs/key.pem -out /opt/Anomaly/node-certs/certificate.pem -days 365 -nodes -subj "/CN=Gozargah"
    chmod 600 /opt/Anomaly/node-certs/key.pem
    chmod 644 /opt/Anomaly/node-certs/certificate.pem
    echo "   ✅ Серверный сертификат сгенерирован"
else
    echo "   ✅ Серверный сертификат уже существует"
fi

# 7. Запуск Docker Compose
echo ""
echo "7️⃣  Запуск Marzban Node..."
cd /opt/Anomaly
docker-compose -f docker-compose.node.yml down || true
docker-compose -f docker-compose.node.yml up -d

echo "   ⏳ Ожидание запуска (10 секунд)..."
sleep 10

# 8. Проверка статуса
echo ""
echo "8️⃣  Проверка статуса..."
if docker ps | grep -q anomaly-node; then
    echo "   ✅ Marzban Node запущен"
    docker logs anomaly-node --tail 20
else
    echo "   ❌ Marzban Node не запущен"
    docker logs anomaly-node --tail 50
    exit 1
fi

echo ""
echo "✅ Установка завершена!"
echo ""
echo "📋 Информация о ноде:"
echo "   IP: $NODE_IP"
echo "   Порт: $NODE_PORT"
echo "   API порт: $API_PORT"
echo "   Control Server: $CONTROL_SERVER_URL"
echo ""


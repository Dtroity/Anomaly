#!/bin/bash

# SSL Setup Script for Anomaly Connect
# Устанавливает SSL сертификаты для всех доменов

set -e

echo "📜 Настройка SSL сертификатов для Anomaly Connect"
echo "=================================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Пожалуйста, запустите от root (используйте sudo)"
    exit 1
fi

# Install certbot if not installed
if ! command -v certbot &> /dev/null; then
    echo "📦 Установка certbot..."
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Domains
DOMAINS=(
    "api.anomaly-connect.online"
    "panel.anomaly-connect.online"
    "anomaly-connect.online"
)

echo "Домены для сертификата:"
for domain in "${DOMAINS[@]}"; do
    echo "  - $domain"
done
echo ""

# Check DNS
echo "⚠️  Убедитесь, что DNS записи настроены:"
echo "  A     api.anomaly-connect.online     → 72.56.79.212"
echo "  A     panel.anomaly-connect.online   → 72.56.79.212"
echo "  A     anomaly-connect.online         → 72.56.79.212"
echo ""
read -p "DNS записи настроены? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Настройте DNS записи и запустите скрипт снова"
    exit 1
fi

# Stop nginx temporarily for standalone mode
echo "🛑 Остановка Nginx..."
docker-compose stop nginx || systemctl stop nginx || true

# Get certificate
echo "📜 Получение SSL сертификата..."
certbot certonly --standalone \
    -d api.anomaly-connect.online \
    -d panel.anomaly-connect.online \
    -d anomaly-connect.online \
    --non-interactive \
    --agree-tos \
    --email admin@anomaly-connect.online

# Create nginx ssl directory
mkdir -p nginx/ssl

# Copy certificates
echo "📋 Копирование сертификатов..."
cp /etc/letsencrypt/live/api.anomaly-connect.online/fullchain.pem nginx/ssl/fullchain.pem
cp /etc/letsencrypt/live/api.anomaly-connect.online/privkey.pem nginx/ssl/privkey.pem

# Set permissions
chmod 644 nginx/ssl/fullchain.pem
chmod 600 nginx/ssl/privkey.pem

# Start nginx
echo "🚀 Запуск Nginx..."
docker-compose start nginx || systemctl start nginx || true

echo ""
echo "✅ SSL сертификаты установлены!"
echo ""
echo "📋 Сертификаты находятся в:"
echo "  /etc/letsencrypt/live/api.anomaly-connect.online/"
echo ""
echo "🔄 Автоматическое обновление настроено через certbot"
echo ""


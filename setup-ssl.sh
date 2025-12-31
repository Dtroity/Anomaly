#!/bin/bash

# SSL Setup Script for Anomaly Connect
# Автоматическая настройка SSL сертификатов через Let's Encrypt

set -e

# Определяем директорию проекта автоматически
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

DOMAINS="anomaly-connect.online api.anomaly-connect.online panel.anomaly-connect.online"
EMAIL="${SSL_EMAIL:-admin@anomaly-connect.online}"

echo "🔐 Настройка SSL сертификатов для Anomaly Connect"
echo "=================================================="
echo ""
echo "Директория проекта: $PROJECT_DIR"
echo "Домены: $DOMAINS"
echo "Email: $EMAIL"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Пожалуйста, запустите от root (используйте sudo)"
    exit 1
fi

# Check DNS propagation
echo "🌐 Проверка DNS записей..."
for domain in $DOMAINS; do
    ip=$(dig +short $domain 2>/dev/null | tail -n1)
    if [ -z "$ip" ]; then
        echo "⚠️  Внимание: DNS для $domain не настроен или не распространился"
        echo "   Продолжить? (y/n)"
        read -r response
        if [ "$response" != "y" ]; then
            echo "❌ Отменено"
            exit 1
        fi
    else
        echo "✅ $domain → $ip"
    fi
done

echo ""
echo "📦 Установка Certbot..."
apt-get update
apt-get install -y certbot python3-certbot-nginx

echo ""
echo "⏸️  Временная остановка Nginx..."
cd "$PROJECT_DIR"
docker-compose stop nginx || true

echo ""
echo "📜 Получение SSL сертификатов..."
certbot certonly --standalone \
    -d anomaly-connect.online \
    -d api.anomaly-connect.online \
    -d panel.anomaly-connect.online \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive

echo ""
echo "📁 Копирование сертификатов..."
mkdir -p "$PROJECT_DIR/nginx/ssl"

# Копируем сертификаты для каждого домена
for domain in api.anomaly-connect.online panel.anomaly-connect.online anomaly-connect.online; do
    mkdir -p "$PROJECT_DIR/nginx/ssl/$domain"
    cp /etc/letsencrypt/live/anomaly-connect.online/fullchain.pem "$PROJECT_DIR/nginx/ssl/$domain/fullchain.pem"
    cp /etc/letsencrypt/live/anomaly-connect.online/privkey.pem "$PROJECT_DIR/nginx/ssl/$domain/privkey.pem"
    chmod 644 "$PROJECT_DIR/nginx/ssl/$domain/fullchain.pem"
    chmod 600 "$PROJECT_DIR/nginx/ssl/$domain/privkey.pem"
done

chown -R "$USER:$USER" "$PROJECT_DIR/nginx/ssl"

echo ""
echo "🔄 Настройка автообновления сертификатов..."
(crontab -l 2>/dev/null | grep -v "certbot renew"; \
 echo "0 */12 * * * certbot renew --quiet --deploy-hook \"cd $PROJECT_DIR && docker-compose restart nginx\"") | crontab -

echo ""
echo "🚀 Запуск Nginx..."
cd "$PROJECT_DIR"
docker-compose up -d nginx

echo ""
echo "✅ SSL сертификаты успешно настроены!"
echo ""
echo "📝 Следующие шаги:"
echo "1. Обновите .env файл:"
echo "   APP_URL=https://api.anomaly-connect.online"
echo "   PANEL_URL=https://panel.anomaly-connect.online"
echo ""
echo "2. Перезапустите сервисы:"
echo "   cd $PROJECT_DIR"
echo "   docker-compose restart api bot"
echo ""
echo "3. Проверьте SSL:"
echo "   curl -I https://api.anomaly-connect.online"
echo ""

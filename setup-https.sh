#!/bin/bash

# Настройка HTTPS после получения SSL сертификатов

set -e

echo "🔐 Настройка HTTPS для Anomaly Connect"
echo "======================================"
echo ""

PROJECT_DIR="/opt/Anomaly"
cd "$PROJECT_DIR"

# 1. Проверить наличие SSL сертификатов
echo "📋 Проверка SSL сертификатов..."
if [ -d "/etc/letsencrypt/live/anomaly-connect.online" ]; then
    echo "✅ SSL сертификаты найдены"
    CERT_PATH="/etc/letsencrypt/live/anomaly-connect.online"
else
    echo "❌ SSL сертификаты не найдены"
    echo "   Запустите: ./setup-ssl.sh"
    exit 1
fi

# 2. Обновить .env файл на HTTPS
echo ""
echo "🔄 Обновление .env файла на HTTPS..."

if [ -f .env ]; then
    # Создать резервную копию
    cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
    
    # Обновить APP_URL и PANEL_URL на HTTPS
    sed -i 's|APP_URL=http://|APP_URL=https://|g' .env
    sed -i 's|PANEL_URL=http://|PANEL_URL=https://|g' .env
    
    echo "✅ .env файл обновлен на HTTPS"
else
    echo "⚠️  Файл .env не найден"
fi

# 3. Настроить Marzban для использования SSL
echo ""
echo "🔄 Настройка Marzban для SSL..."

if [ -f .env.marzban ]; then
    # Создать резервную копию
    cp .env.marzban .env.marzban.backup.$(date +%Y%m%d_%H%M%S)
    
    # Обновить UVICORN_SSL_CERTFILE и UVICORN_SSL_KEYFILE
    # Marzban будет использовать SSL внутри контейнера
    # Но для доступа через Nginx можно оставить без SSL в Marzban
    
    # Обновить XRAY_SUBSCRIPTION_URL_PREFIX на HTTPS
    sed -i 's|XRAY_SUBSCRIPTION_URL_PREFIX=http://|XRAY_SUBSCRIPTION_URL_PREFIX=https://|g' .env.marzban
    
    echo "✅ .env.marzban обновлен"
else
    echo "⚠️  Файл .env.marzban не найден"
fi

# 4. Переключить Nginx на SSL конфигурацию
echo ""
echo "🔄 Переключение Nginx на SSL конфигурацию..."

cd nginx/conf.d

# Сохранить HTTP конфигурацию
if [ -f default.conf ] && ! grep -q "listen 443 ssl" default.conf; then
    mv default.conf default-http.conf.bak
    echo "✅ HTTP конфигурация сохранена"
fi

# Использовать SSL конфигурацию (если есть)
if [ -f default-ssl.conf.bak ]; then
    cp default-ssl.conf.bak default.conf
    echo "✅ SSL конфигурация восстановлена"
elif [ -f default.conf ] && grep -q "listen 443 ssl" default.conf; then
    echo "✅ SSL конфигурация уже используется"
else
    echo "⚠️  SSL конфигурация не найдена, создаю базовую..."
    # Создать базовую SSL конфигурацию
    cat > default.conf << 'EOF'
# HTTPS - API Server
server {
    listen 443 ssl http2;
    server_name api.anomaly-connect.online;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    location / {
        proxy_pass http://api:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTPS - Panel
server {
    listen 443 ssl http2;
    server_name panel.anomaly-connect.online;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    location / {
        proxy_pass http://marzban:62050/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name api.anomaly-connect.online panel.anomaly-connect.online;
    return 301 https://$host$request_uri;
}
EOF
    echo "✅ Базовая SSL конфигурация создана"
fi

cd ../..

# 5. Копировать сертификаты в директорию Nginx (если нужно)
echo ""
echo "📁 Копирование сертификатов..."
mkdir -p nginx/ssl

if [ -f "$CERT_PATH/fullchain.pem" ] && [ -f "$CERT_PATH/privkey.pem" ]; then
    cp "$CERT_PATH/fullchain.pem" nginx/ssl/
    cp "$CERT_PATH/privkey.pem" nginx/ssl/
    chmod 644 nginx/ssl/fullchain.pem
    chmod 600 nginx/ssl/privkey.pem
    echo "✅ Сертификаты скопированы"
else
    echo "⚠️  Сертификаты не найдены в $CERT_PATH"
fi

# 6. Перезапустить сервисы
echo ""
echo "🔄 Перезапуск сервисов..."
docker-compose restart api bot nginx

# Подождать
sleep 5

# 7. Проверить статус
echo ""
echo "📊 Статус сервисов:"
docker-compose ps

# 8. Проверить HTTPS
echo ""
echo "🌐 Проверка HTTPS:"
echo -n "  API: "
curl -s -o /dev/null -w "%{http_code}" https://api.anomaly-connect.online/health 2>/dev/null && echo "✅" || echo "❌"

echo -n "  Panel: "
curl -s -o /dev/null -w "%{http_code}" https://panel.anomaly-connect.online/ 2>/dev/null && echo "✅" || echo "❌"

echo ""
echo "✅ Готово!"
echo ""
echo "📝 Проверьте:"
echo "  - https://api.anomaly-connect.online/health"
echo "  - https://panel.anomaly-connect.online"
echo "  - Бот в Telegram: @Anomaly_connectBot"


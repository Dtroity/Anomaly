#!/bin/bash

# Скрипт для исправления Nginx и проверки бота

set -e

echo "🔧 Исправление Nginx и проверка бота..."
echo ""

# 1. Проверить логи Nginx
echo "📋 Логи Nginx (последние 30 строк):"
docker-compose logs --tail=30 nginx
echo ""

# 2. Остановить Nginx
echo "⏸️  Остановка Nginx..."
docker-compose stop nginx

# 3. Переключить на HTTP конфигурацию (без SSL)
echo "🔄 Переключение на HTTP конфигурацию..."
cd nginx/conf.d

# Сохранить SSL конфигурации (если есть)
if [ -f default.conf ]; then
    mv default.conf default-ssl.conf.bak 2>/dev/null || true
fi
if [ -f main.conf ]; then
    mv main.conf main-ssl.conf.bak 2>/dev/null || true
fi
if [ -f panel.conf ]; then
    mv panel.conf panel-ssl.conf.bak 2>/dev/null || true
fi

# Удалить все SSL конфигурации временно
rm -f default.conf main.conf panel.conf 2>/dev/null || true

# Использовать HTTP конфигурацию
if [ -f default-http-only.conf ]; then
    cp default-http-only.conf default.conf
    echo "✅ Использована HTTP конфигурация"
else
    echo "⚠️  Файл default-http-only.conf не найден, создаю базовую конфигурацию..."
    cat > default.conf << 'EOF'
# HTTP - API Server (временно, до получения SSL)
server {
    listen 80;
    server_name api.anomaly-connect.online;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://api:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP - Panel
server {
    listen 80;
    server_name panel.anomaly-connect.online;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://marzban:62050/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# HTTP - Main domain
server {
    listen 80;
    server_name anomaly-connect.online;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 "Anomaly Connect - Coming Soon";
        add_header Content-Type text/plain;
    }
}
EOF
fi

cd ../..

# 4. Запустить только Nginx (без пересоздания других контейнеров)
echo "🚀 Запуск Nginx..."
docker-compose up -d --no-deps nginx

# 5. Проверить логи бота
echo ""
echo "📋 Логи бота (последние 30 строк):"
docker-compose logs --tail=30 bot
echo ""

# 6. Проверить статус
echo "📊 Статус всех сервисов:"
docker-compose ps

echo ""
echo "✅ Готово!"
echo ""
echo "📝 Проверьте:"
echo "  1. HTTP доступность: curl http://api.anomaly-connect.online/health"
echo "  2. Логи Nginx: docker-compose logs -f nginx"
echo "  3. Логи бота: docker-compose logs -f bot"
echo "  4. Проверьте BOT_TOKEN в .env файле"


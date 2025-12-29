#!/bin/bash

# Anomaly VPN - Control Server Installation
# VPS #1 (72.56.79.212)

set -e

echo "🚀 Установка Anomaly VPN Control Server"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Пожалуйста, запустите от root (используйте sudo)"
    exit 1
fi

# Update system
echo "📦 Обновление системных пакетов..."
apt-get update
apt-get upgrade -y

# Install required packages
echo "📦 Установка необходимых пакетов..."
apt-get install -y \
    curl \
    wget \
    git \
    docker.io \
    docker-compose \
    certbot \
    python3-certbot-nginx

# Start and enable Docker
echo "🐳 Настройка Docker..."
systemctl start docker
systemctl enable docker

# Create project directory
PROJECT_DIR="/opt/anomaly-vpn"
echo "📁 Создание директории проекта: $PROJECT_DIR"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy project files if not already there
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo "📥 Копирование файлов проекта..."
    if [ -d "$SCRIPT_DIR" ]; then
        cp -r "$SCRIPT_DIR"/* "$PROJECT_DIR/" 2>/dev/null || true
    fi
fi

# Create directories
echo "📁 Создание директорий..."
mkdir -p nginx/conf.d
mkdir -p nginx/ssl
mkdir -p vpnbot/data
mkdir -p vpnbot/logs

# Create .env files if they don't exist
if [ ! -f .env ]; then
    echo "📝 Создание .env файла..."
    if [ -f .env.template ]; then
        cp .env.template .env
    fi
    echo ""
    echo "⚠️  ВАЖНО: Отредактируйте .env файл:"
    echo "   nano $PROJECT_DIR/.env"
    echo ""
    read -p "Нажмите Enter после настройки .env файла..."
fi

if [ ! -f .env.marzban ]; then
    echo "📝 Создание .env.marzban файла..."
    if [ -f .env.marzban.template ]; then
        cp .env.marzban.template .env.marzban
    fi
    echo ""
    echo "⚠️  ВАЖНО: Отредактируйте .env.marzban файл:"
    echo "   nano $PROJECT_DIR/.env.marzban"
    echo ""
    read -p "Нажмите Enter после настройки .env.marzban файла..."
fi

# Setup SSL certificates
echo ""
echo "📜 Настройка SSL сертификатов..."
echo "Домены для сертификата:"
echo "  - api.anomaly-connect.online"
echo "  - panel.anomaly-connect.online"
echo "  - anomaly-connect.online"
echo ""
read -p "Хотите настроить SSL сертификаты сейчас? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    certbot certonly --standalone \
        -d api.anomaly-connect.online \
        -d panel.anomaly-connect.online \
        -d anomaly-connect.online
    
    # Copy certificates to nginx directory
    cp /etc/letsencrypt/live/api.anomaly-connect.online/fullchain.pem nginx/ssl/fullchain.pem
    cp /etc/letsencrypt/live/api.anomaly-connect.online/privkey.pem nginx/ssl/privkey.pem
    
    echo "✅ SSL сертификаты установлены"
fi

# Build and start services
echo "🐳 Сборка Docker образов..."
docker-compose build

echo "🚀 Запуск сервисов..."
docker-compose up -d

# Wait for services to start
echo "⏳ Ожидание запуска сервисов..."
sleep 15

# Check service status
echo ""
echo "📊 Статус сервисов:"
docker-compose ps

# Create admin user in Marzban
echo ""
echo "👤 Создание администратора Marzban..."
docker-compose exec marzban marzban cli admin create --sudo || echo "Администратор уже существует"

echo ""
echo "✅ Установка завершена!"
echo ""
echo "📋 Следующие шаги:"
echo "  1. Настройте .env и .env.marzban файлы"
echo "  2. Проверьте статус: docker-compose ps"
echo "  3. Проверьте логи: docker-compose logs -f"
echo "  4. Откройте панель Marzban: https://your-domain.com/marzban/"
echo "  5. Протестируйте бота: отправьте /start в Telegram"
echo ""
echo "📊 Полезные команды:"
echo "  docker-compose ps              - Статус сервисов"
echo "  docker-compose logs -f         - Логи всех сервисов"
echo "  docker-compose logs -f bot     - Логи бота"
echo "  docker-compose restart bot     - Перезапуск бота"
echo "  docker-compose restart api     - Перезапуск API"
echo ""


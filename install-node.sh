#!/bin/bash

# Anomaly VPN - Node Installation
# VPS #2 (Worker Node)

set -e

echo "🚀 Установка Anomaly VPN Node"
echo "============================="
echo ""
echo "⚠️  Этот скрипт установит Marzban Node на VPS #2"
echo "    Убедитесь, что вы запускаете это на правильном сервере!"
echo ""
read -p "Продолжить? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

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
    docker-compose

# Start and enable Docker
echo "🐳 Настройка Docker..."
systemctl start docker
systemctl enable docker

# Create project directory
PROJECT_DIR="/opt/anomaly-node"
echo "📁 Создание директории проекта: $PROJECT_DIR"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy project files
echo "📥 Копирование файлов проекта..."
if [ -f "$SCRIPT_DIR/docker-compose.node.yml" ]; then
    cp "$SCRIPT_DIR/docker-compose.node.yml" "$PROJECT_DIR/docker-compose.yml"
fi

# Create .env.node file
if [ ! -f .env.node ]; then
    echo "📝 Создание .env.node файла..."
    if [ -f "$SCRIPT_DIR/.env.node.template" ]; then
        cp "$SCRIPT_DIR/.env.node.template" .env.node
    fi
    
    echo ""
    echo "⚠️  ВАЖНО: Отредактируйте .env.node файл:"
    echo "   nano $PROJECT_DIR/.env.node"
    echo ""
    echo "Обязательно укажите:"
    echo "  - CONTROL_SERVER_URL: URL Control Server (VPS #1)"
    echo "  - CONTROL_SERVER_PASSWORD: Пароль Marzban"
    echo "  - NODE_ID: Уникальный ID ноды"
    echo ""
    read -p "Нажмите Enter после настройки .env.node файла..."
fi

# Setup firewall
echo "🔥 Настройка firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 443/tcp comment "VLESS Reality"
    ufw allow 80/tcp comment "HTTP Fallback"
    ufw allow 22/tcp comment "SSH"
    ufw enable
fi

# Build and start services
echo "🐳 Сборка Docker образа..."
docker-compose build

echo "🚀 Запуск Node..."
docker-compose up -d

# Wait for services to start
echo "⏳ Ожидание запуска..."
sleep 10

# Check service status
echo ""
echo "📊 Статус Node:"
docker-compose ps

echo ""
echo "✅ Node установлен и запущен!"
echo ""
echo "📋 Следующие шаги:"
echo "  1. Настройте .env.node файл"
echo "  2. Зарегистрируйте ноду в Marzban на Control Server"
echo "  3. Проверьте статус: docker-compose ps"
echo "  4. Проверьте логи: docker-compose logs -f"
echo ""
echo "📊 Полезные команды:"
echo "  docker-compose ps              - Статус"
echo "  docker-compose logs -f         - Логи"
echo "  docker-compose restart         - Перезапуск"
echo ""


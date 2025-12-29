#!/bin/bash

# Anomaly VPN Bot Installation Script
# Установка бота и API напрямую на VPS #1 (Control Plane)

set -e

echo "🚀 Установка Anomaly VPN Bot"
echo "============================"
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
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    python3-dev \
    libssl-dev \
    libffi-dev \
    postgresql \
    postgresql-contrib \
    nginx \
    certbot \
    python3-certbot-nginx \
    supervisor

# Start and enable PostgreSQL
echo "🗄️  Настройка PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Create project directory
PROJECT_DIR="/opt/anomaly-vpn"
echo "📁 Создание директории проекта: $PROJECT_DIR"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy project files if not already there
if [ ! -f "$PROJECT_DIR/vpnbot/main.py" ]; then
    echo "📥 Копирование файлов проекта..."
    if [ -d "$SCRIPT_DIR/vpnbot" ]; then
        cp -r "$SCRIPT_DIR"/* "$PROJECT_DIR/" 2>/dev/null || true
    else
        echo "⚠️  Файлы проекта не найдены в $SCRIPT_DIR"
        echo "   Убедитесь, что все файлы скопированы в $PROJECT_DIR"
    fi
fi

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Создание .env файла из шаблона..."
    if [ -f .env.template ]; then
        cp .env.template .env
    else
        echo "⚠️  .env.template не найден, создаю базовый .env"
        cat > .env << EOF
# Telegram Bot
BOT_TOKEN=your_telegram_bot_token_here
ADMIN_IDS=123456789,987654321

# Database
DB_NAME=anomaly
DB_USER=anomaly
DB_PASSWORD=change_me_strong_password
DB_HOST=localhost
DB_PORT=5432

# Marzban API (VPS #2 - VPN Node)
MARZBAN_API_URL=https://your-vpn-node-ip:62050
MARZBAN_USERNAME=root
MARZBAN_PASSWORD=your_marzban_password

# YooKassa
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key
YOOKASSA_TEST_MODE=true

# Telegram Payments
TELEGRAM_PAYMENT_PROVIDER_TOKEN=your_provider_token

# Application
APP_NAME=Anomaly
APP_URL=https://your-domain.com
API_SECRET_KEY=generate_random_secret_key_here

# VPN Settings
DEFAULT_TRAFFIC_LIMIT_GB=100
DEFAULT_MAX_DEVICES=3
FREE_TRIAL_DAYS=7
FREE_TRIAL_TRAFFIC_GB=5

# Nodes Configuration (JSON format)
NODES_CONFIG=[]
EOF
    fi
    
    echo ""
    echo "⚠️  ВАЖНО: Отредактируйте .env файл и настройте все параметры:"
    echo "   nano $PROJECT_DIR/.env"
    echo ""
    echo "Обязательные настройки:"
    echo "  - BOT_TOKEN: Токен Telegram бота"
    echo "  - ADMIN_IDS: ID администраторов (через запятую)"
    echo "  - MARZBAN_API_URL: URL вашего Marzban инстанса"
    echo "  - MARZBAN_USERNAME: Логин Marzban"
    echo "  - MARZBAN_PASSWORD: Пароль Marzban"
    echo "  - YOOKASSA_SHOP_ID: ID магазина ЮKassa"
    echo "  - YOOKASSA_SECRET_KEY: Секретный ключ ЮKassa"
    echo "  - APP_URL: URL вашего домена"
    echo ""
    read -p "Нажмите Enter после настройки .env файла..."
fi

# Create directories
echo "📁 Создание директорий..."
mkdir -p vpnbot/data
mkdir -p vpnbot/logs
chmod 755 vpnbot/data
chmod 755 vpnbot/logs

# Setup Python virtual environment
echo "🐍 Настройка виртуального окружения Python..."
cd vpnbot
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
echo "📦 Установка зависимостей Python..."
pip install --upgrade pip
pip install -r requirements.txt

# Setup PostgreSQL database
echo "🗄️  Настройка базы данных PostgreSQL..."
source ../.env 2>/dev/null || true

# Create database and user
sudo -u postgres psql << EOF
CREATE DATABASE ${DB_NAME:-anomaly};
CREATE USER ${DB_USER:-anomaly} WITH PASSWORD '${DB_PASSWORD:-change_me}';
ALTER ROLE ${DB_USER:-anomaly} SET client_encoding TO 'utf8';
ALTER ROLE ${DB_USER:-anomaly} SET default_transaction_isolation TO 'read committed';
ALTER ROLE ${DB_USER:-anomaly} SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME:-anomaly} TO ${DB_USER:-anomaly};
\q
EOF

# Initialize database
echo "🗄️  Инициализация базы данных..."
python3 -c "from database import init_db; init_db()" || echo "База данных уже инициализирована"

cd ..

# Create systemd service for bot
echo "⚙️  Создание systemd сервиса для бота..."
cat > /etc/systemd/system/anomaly-bot.service << EOF
[Unit]
Description=Anomaly VPN Telegram Bot
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/vpnbot
Environment="PATH=$PROJECT_DIR/vpnbot/venv/bin"
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/vpnbot/venv/bin/python $PROJECT_DIR/vpnbot/main.py
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_DIR/vpnbot/logs/bot.log
StandardError=append:$PROJECT_DIR/vpnbot/logs/bot.error.log

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for API
echo "⚙️  Создание systemd сервиса для API..."
cat > /etc/systemd/system/anomaly-api.service << EOF
[Unit]
Description=Anomaly VPN API
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/vpnbot
Environment="PATH=$PROJECT_DIR/vpnbot/venv/bin"
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/vpnbot/venv/bin/uvicorn api:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_DIR/vpnbot/logs/api.log
StandardError=append:$PROJECT_DIR/vpnbot/logs/api.error.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Setup Nginx (basic configuration)
echo "🌐 Настройка Nginx..."
if [ ! -f /etc/nginx/sites-available/anomaly ]; then
    cat > /etc/nginx/sites-available/anomaly << 'NGINX_CONFIG'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_CONFIG

    ln -sf /etc/nginx/sites-available/anomaly /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
fi

# Start and enable services
echo "🚀 Запуск сервисов..."
systemctl enable anomaly-bot
systemctl enable anomaly-api
systemctl start anomaly-bot
systemctl start anomaly-api

# Wait a bit for services to start
sleep 5

# Check service status
echo ""
echo "📊 Статус сервисов:"
echo "================================"
systemctl status anomaly-bot --no-pager -l || true
echo ""
systemctl status anomaly-api --no-pager -l || true

echo ""
echo "✅ Установка завершена!"
echo ""
echo "📋 Следующие шаги:"
echo "  1. Настройте .env файл: nano $PROJECT_DIR/.env"
echo "  2. Перезапустите сервисы: systemctl restart anomaly-bot anomaly-api"
echo "  3. Проверьте логи: journalctl -u anomaly-bot -f"
echo "  4. Протестируйте бота: отправьте /start вашему Telegram боту"
echo ""
echo "📚 Документация:"
echo "  - README.md: Общая информация"
echo "  - docs/ADMIN.md: Руководство администратора"
echo "  - docs/CLIENTS.md: Руководство для клиентов"
echo "  - DEPLOYMENT.md: Детальное развертывание"
echo ""
echo "📊 Полезные команды:"
echo "  systemctl status anomaly-bot    - Статус бота"
echo "  systemctl status anomaly-api     - Статус API"
echo "  journalctl -u anomaly-bot -f     - Логи бота"
echo "  journalctl -u anomaly-api -f     - Логи API"
echo "  systemctl restart anomaly-bot    - Перезапуск бота"
echo "  systemctl restart anomaly-api     - Перезапуск API"
echo ""

#!/bin/bash

# Marzban Installation Script for VPS #2 (VPN Node)
# Установка Marzban напрямую на сервер из готовой директории

set -e

echo "🚀 Установка Marzban для Anomaly VPN"
echo "===================================="
echo ""
echo "⚠️  Этот скрипт установит Marzban на VPS #2 (VPN Node)"
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
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    python3-dev \
    libssl-dev \
    libffi-dev \
    sqlite3

# Install Xray
echo "📦 Установка Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Get project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARZBAN_SOURCE_DIR="$SCRIPT_DIR/Marzban-0.8.4"

# Check if Marzban source exists
if [ ! -d "$MARZBAN_SOURCE_DIR" ]; then
    echo "❌ Директория Marzban-0.8.4 не найдена!"
    echo "   Убедитесь, что файлы Marzban находятся в $MARZBAN_SOURCE_DIR"
    exit 1
fi

# Installation directory
MARZBAN_DIR="/opt/marzban"
MARZBAN_DATA_DIR="/var/lib/marzban"

echo "📁 Копирование файлов Marzban..."
mkdir -p "$MARZBAN_DIR"
mkdir -p "$MARZBAN_DATA_DIR"

# Copy Marzban files
cp -r "$MARZBAN_SOURCE_DIR"/* "$MARZBAN_DIR/"
cd "$MARZBAN_DIR"

# Create virtual environment
echo "🐍 Создание виртуального окружения Python..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
echo "📦 Установка зависимостей Python..."
pip install --upgrade pip
pip install -r requirements.txt

# Run database migrations
echo "🗄️  Настройка базы данных..."
alembic upgrade head

# Create .env file if it doesn't exist
if [ ! -f "$MARZBAN_DIR/.env" ]; then
    echo "📝 Создание файла конфигурации..."
    
    # Check for .env.example
    if [ -f "$MARZBAN_DIR/.env.example" ]; then
        cp "$MARZBAN_DIR/.env.example" "$MARZBAN_DIR/.env"
    else
        # Create basic .env
        cat > "$MARZBAN_DIR/.env" << EOF
# Marzban Configuration
UVICORN_HOST=0.0.0.0
UVICORN_PORT=62050
UVICORN_SSL_CERTFILE=
UVICORN_SSL_KEYFILE=
UVICORN_SSL_CA_TYPE=
UVICORN_UDS=

# Database
DATABASE_URL=sqlite:///$MARZBAN_DATA_DIR/db.sqlite3

# Xray
XRAY_EXECUTABLE_PATH=/usr/local/bin/xray
XRAY_ASSETS_PATH=/usr/local/share/xray
XRAY_JSON=/var/lib/marzban/xray_config.json

# Security
SUDO_USERNAME=root
SUDO_PASSWORD=root

# Subscription
XRAY_SUBSCRIPTION_PATH=sub
XRAY_SUBSCRIPTION_URL_PREFIX=https://YOUR_DOMAIN_OR_IP
EOF
    fi
    
    echo ""
    echo "⚠️  ВАЖНО: Отредактируйте файл конфигурации:"
    echo "   nano $MARZBAN_DIR/.env"
    echo ""
    echo "Обязательно измените:"
    echo "  - SUDO_PASSWORD: установите надежный пароль"
    echo "  - XRAY_SUBSCRIPTION_URL_PREFIX: укажите ваш домен или IP"
    echo ""
    read -p "Нажмите Enter после настройки .env файла..."
fi

# Install marzban-cli
echo "🔧 Установка Marzban CLI..."
ln -sf "$MARZBAN_DIR/marzban-cli.py" /usr/local/bin/marzban
chmod +x /usr/local/bin/marzban
marzban completion install || true

# Create systemd service
echo "⚙️  Создание systemd сервиса..."
cat > /etc/systemd/system/marzban.service << EOF
[Unit]
Description=Marzban VPN Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$MARZBAN_DIR
Environment="PATH=$MARZBAN_DIR/venv/bin"
ExecStart=$MARZBAN_DIR/venv/bin/python $MARZBAN_DIR/main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Create admin user if not exists
echo "👤 Создание администратора..."
if ! marzban cli admin list | grep -q "root"; then
    echo "Создание администратора root..."
    marzban cli admin create --sudo || echo "Администратор уже существует или произошла ошибка"
fi

# Setup firewall
echo "🔥 Настройка firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 62050/tcp comment "Marzban Panel"
    ufw allow 443/tcp comment "VLESS Reality"
    ufw allow 80/tcp comment "HTTP"
    echo "Правила firewall добавлены"
fi

# Start and enable service
echo "🚀 Запуск Marzban..."
systemctl enable marzban
systemctl start marzban

# Wait a bit for service to start
sleep 5

# Check status
if systemctl is-active --quiet marzban; then
    echo "✅ Marzban успешно установлен и запущен!"
else
    echo "⚠️  Marzban установлен, но не запущен. Проверьте логи:"
    echo "   journalctl -u marzban -f"
fi

echo ""
echo "📋 Информация об установке:"
echo "================================"
echo "📁 Директория: $MARZBAN_DIR"
echo "📁 Данные: $MARZBAN_DATA_DIR"
echo "⚙️  Конфигурация: $MARZBAN_DIR/.env"
echo "🌐 Панель: https://YOUR_IP:62050/dashboard/"
echo ""
echo "📊 Полезные команды:"
echo "  systemctl status marzban    - Статус сервиса"
echo "  systemctl restart marzban   - Перезапуск"
echo "  journalctl -u marzban -f    - Логи"
echo "  marzban cli admin list       - Список админов"
echo ""
echo "🔐 API Configuration для VPS #1 (.env файл):"
echo "  MARZBAN_API_URL=https://YOUR_SERVER_IP:62050"
echo "  MARZBAN_USERNAME=root"
echo "  MARZBAN_PASSWORD=your_password"
echo ""
echo "⚠️  Рекомендации по безопасности:"
echo "  - Смените пароль администратора"
echo "  - Настройте firewall для ограничения доступа"
echo "  - Используйте SSL сертификат для панели"
echo "  - Не открывайте панель Marzban публично (используйте VPN или ограничьте IP)"
echo ""

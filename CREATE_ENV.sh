#!/bin/bash

# Скрипт для создания .env файла на сервере
# Используйте если env.before-ssl.template отсутствует

set -e

echo "📝 Создание .env файла для Anomaly Connect"
echo "=========================================="
echo ""

# Определяем директорию проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
cd "$PROJECT_DIR"

# Создаем .env файл
cat > .env << 'EOF'
# ============================================
# Anomaly Connect - .env файл ДО получения SSL
# Используйте этот файл до настройки SSL сертификата
# ============================================

# ============================================
# Telegram Bot
# ============================================
BOT_TOKEN=your_telegram_bot_token_here
ADMIN_IDS=your_telegram_id_1,your_telegram_id_2

# ============================================
# Database (PostgreSQL)
# ============================================
DB_NAME=anomaly
DB_USER=anomaly
DB_PASSWORD=change_me_to_strong_password
DB_HOST=db
DB_PORT=5432

# ============================================
# Marzban (локально на Control Server)
# ============================================
MARZBAN_API_URL=http://marzban:62050
MARZBAN_USERNAME=root
MARZBAN_PASSWORD=change_me_to_strong_password

# ============================================
# YooKassa Payment Gateway
# ============================================
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key
YOOKASSA_TEST_MODE=true

# ============================================
# Telegram Payments (опционально)
# ============================================
TELEGRAM_PAYMENT_PROVIDER_TOKEN=

# ============================================
# Crypto Payments (опционально)
# ============================================
CRYPTO_WALLET_ADDRESS=
CRYPTO_NETWORK=TRC20

# ============================================
# Application Settings
# ============================================
APP_NAME=Anomaly Connect

# ⚠️ ВАЖНО: Используйте HTTP до получения SSL!
APP_URL=http://api.anomaly-connect.online
PANEL_URL=http://panel.anomaly-connect.online

# Секретный ключ для API (сгенерируйте случайную строку)
API_SECRET_KEY=generate_random_secret_key_min_32_chars

# ============================================
# VPN Settings
# ============================================
DEFAULT_TRAFFIC_LIMIT_GB=100
DEFAULT_MAX_DEVICES=3

# ============================================
# Free/Trial Settings
# ============================================
FREE_TRIAL_DAYS=7
FREE_TRIAL_TRAFFIC_GB=5

# ============================================
# Nodes Configuration
# ============================================
# Формат JSON массива с информацией о нодах
# Пример:
# NODES_CONFIG=[{"id":"node1","url":"http://node1.example.com:62050","username":"root","password":"pass"}]
NODES_CONFIG=[]

# ============================================
# Инструкции по заполнению:
# ============================================
# 1. BOT_TOKEN - получите у @BotFather в Telegram
# 2. ADMIN_IDS - ваш Telegram ID (можно узнать у @userinfobot)
# 3. DB_PASSWORD - придумайте надежный пароль для PostgreSQL
# 4. MARZBAN_PASSWORD - пароль для Marzban (будет установлен при первом запуске)
# 5. YOOKASSA_SHOP_ID и YOOKASSA_SECRET_KEY - получите в личном кабинете ЮKassa
# 6. API_SECRET_KEY - сгенерируйте случайную строку (минимум 32 символа)
#    Можно использовать: openssl rand -hex 32
#
# ⚠️ ВАЖНО:
# - До получения SSL используйте HTTP (http://) в APP_URL и PANEL_URL
# - После получения SSL обновите на HTTPS (https://)
# - Не используйте этот файл в продакшене без изменения паролей!
# ============================================
EOF

echo "✅ Файл .env создан!"
echo ""
echo "📝 Теперь отредактируйте .env файл:"
echo "   nano $PROJECT_DIR/.env"
echo ""
echo "⚠️  Обязательно заполните:"
echo "   - BOT_TOKEN (получите у @BotFather)"
echo "   - ADMIN_IDS (ваш Telegram ID)"
echo "   - DB_PASSWORD (надежный пароль)"
echo "   - MARZBAN_PASSWORD (надежный пароль)"
echo "   - API_SECRET_KEY (сгенерируйте: openssl rand -hex 32)"
echo ""


#!/bin/bash

# Скрипт для создания .env.marzban файла на сервере
# Используйте если env.marzban.template отсутствует

set -e

echo "📝 Создание .env.marzban файла для Anomaly Connect"
echo "=================================================="
echo ""

# Определяем директорию проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
cd "$PROJECT_DIR"

# Проверяем наличие .env для получения DB_PASSWORD
if [ -f ".env" ]; then
    # Пытаемся извлечь DB_PASSWORD из .env
    DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" || echo "change_me_to_strong_password")
    echo "✅ Найден .env файл, используем DB_PASSWORD из него"
else
    DB_PASSWORD="change_me_to_strong_password"
    echo "⚠️  .env файл не найден, используем дефолтный пароль"
    echo "   После создания .env обновите DATABASE_URL в .env.marzban"
fi

# Создаем .env.marzban файл
cat > .env.marzban << EOF
# Marzban Configuration (Control Server)
# Скопируйте в .env.marzban и настройте

# Server
UVICORN_HOST=0.0.0.0
UVICORN_PORT=62050
UVICORN_SSL_CERTFILE=
UVICORN_SSL_KEYFILE=
UVICORN_SSL_CA_TYPE=
UVICORN_UDS=

# Database (использует общую БД PostgreSQL)
# ⚠️ ВАЖНО: Замените \${DB_PASSWORD} на реальный пароль из .env!
DATABASE_URL=postgresql://anomaly:${DB_PASSWORD}@db:5432/marzban

# Xray
XRAY_EXECUTABLE_PATH=/usr/local/bin/xray
XRAY_ASSETS_PATH=/usr/local/share/xray
XRAY_JSON=/var/lib/marzban/xray_config.json

# Security
SUDO_USERNAME=root
SUDO_PASSWORD=change_me_marzban_password

# Subscription
XRAY_SUBSCRIPTION_PATH=sub
# ⚠️ ВАЖНО: Используйте HTTP до получения SSL, затем обновите на HTTPS
XRAY_SUBSCRIPTION_URL_PREFIX=http://api.anomaly-connect.online

# Nodes
NODES_IPS=
EOF

echo "✅ Файл .env.marzban создан!"
echo ""
echo "📝 Теперь отредактируйте .env.marzban файл:"
echo "   nano $PROJECT_DIR/.env.marzban"
echo ""
echo "⚠️  Обязательно обновите:"
echo "   1. DATABASE_URL - используйте тот же DB_PASSWORD, что и в .env"
echo "   2. SUDO_PASSWORD - надежный пароль для Marzban админа"
echo "   3. XRAY_SUBSCRIPTION_URL_PREFIX - после получения SSL измените на https://"
echo ""


#!/bin/bash

# Start Anomaly VPN Bot services (systemd)

set -e

PROJECT_DIR="/opt/anomaly-vpn"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Директория проекта не найдена: $PROJECT_DIR"
    echo "Пожалуйста, сначала запустите install.sh"
    exit 1
fi

echo "🚀 Запуск Anomaly VPN Bot сервисов..."

# Check if .env exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "❌ .env файл не найден!"
    echo "Пожалуйста, создайте .env файл из .env.template"
    exit 1
fi

# Start PostgreSQL if not running
systemctl start postgresql || true

# Start services
systemctl start anomaly-bot
systemctl start anomaly-api

echo "✅ Сервисы запущены!"
echo ""
echo "📊 Проверка статуса:"
echo "  systemctl status anomaly-bot"
echo "  systemctl status anomaly-api"
echo ""
echo "📋 Просмотр логов:"
echo "  journalctl -u anomaly-bot -f"
echo "  journalctl -u anomaly-api -f"
echo ""
echo "🛑 Остановка сервисов:"
echo "  systemctl stop anomaly-bot anomaly-api"

#!/bin/bash

# Setup Cron Jobs for Anomaly Connect
# Настройка автоматических задач

set -e

echo "⏰ Настройка автоматических задач"
echo "=================================="
echo ""

PROJECT_DIR="/opt/anomaly-vpn"
BACKUP_SCRIPT="$PROJECT_DIR/backup.sh"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Пожалуйста, запустите от root (используйте sudo)"
    exit 1
fi

# Add backup cron job (daily at 3:00 AM)
echo "📦 Настройка ежедневного бэкапа (3:00 AM)..."
(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT"; echo "0 3 * * * $BACKUP_SCRIPT >> $PROJECT_DIR/logs/backup.log 2>&1") | crontab -

# Add log rotation (weekly)
echo "📋 Настройка ротации логов (еженедельно)..."
(crontab -l 2>/dev/null | grep -v "logrotate"; echo "0 2 * * 0 find $PROJECT_DIR/vpnbot/logs -name '*.log' -mtime +7 -delete") | crontab -

# Add health check (every 5 minutes)
echo "🏥 Настройка проверки здоровья сервисов (каждые 5 минут)..."
(crontab -l 2>/dev/null | grep -v "health-check"; echo "*/5 * * * * cd $PROJECT_DIR && docker-compose ps | grep -q 'Up' || docker-compose restart >> $PROJECT_DIR/logs/health.log 2>&1") | crontab -

echo ""
echo "✅ Автоматические задачи настроены!"
echo ""
echo "📋 Текущие задачи cron:"
crontab -l
echo ""


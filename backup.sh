#!/bin/bash

# Backup Script for Anomaly Connect
# Создает резервные копии базы данных и конфигурации

set -e

# Определяем директорию проекта автоматически
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BACKUP_DIR="$PROJECT_DIR/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "💾 Создание резервной копии Anomaly Connect"
echo "============================================"
echo ""
echo "Директория проекта: $PROJECT_DIR"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup PostgreSQL database
echo "📦 Резервное копирование базы данных..."
cd "$PROJECT_DIR"
DB_NAME=${DB_NAME:-anomaly}
DB_USER=${DB_USER:-anomaly}
DB_PASSWORD=${DB_PASSWORD:-change_me}

PGPASSWORD=$DB_PASSWORD docker-compose exec -T db pg_dump -U $DB_USER $DB_NAME > "$BACKUP_DIR/db_$DATE.sql"

# Compress database backup
gzip "$BACKUP_DIR/db_$DATE.sql"
echo "✅ База данных сохранена: db_$DATE.sql.gz"

# Backup .env files
echo "📦 Резервное копирование конфигурации..."
cp "$PROJECT_DIR/.env" "$BACKUP_DIR/env_$DATE.backup" 2>/dev/null || true
cp "$PROJECT_DIR/.env.marzban" "$BACKUP_DIR/env_marzban_$DATE.backup" 2>/dev/null || true
echo "✅ Конфигурация сохранена"

# Backup logs (optional, last 7 days)
echo "📦 Резервное копирование логов..."
if [ -d "$PROJECT_DIR/vpnbot/logs" ]; then
    tar -czf "$BACKUP_DIR/logs_$DATE.tar.gz" -C "$PROJECT_DIR/vpnbot" logs/ 2>/dev/null || true
    echo "✅ Логи сохранены: logs_$DATE.tar.gz"
fi

# Remove old backups (older than 30 days)
echo "🧹 Удаление старых бэкапов (старше 30 дней)..."
find "$BACKUP_DIR" -type f -mtime +30 -delete
echo "✅ Старые бэкапы удалены"

# Show backup info
echo ""
echo "📊 Информация о резервной копии:"
echo "================================"
ls -lh "$BACKUP_DIR" | tail -5
echo ""
echo "✅ Резервное копирование завершено!"
echo "📁 Директория: $BACKUP_DIR"

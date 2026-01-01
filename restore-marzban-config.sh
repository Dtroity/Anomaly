#!/bin/bash

echo "🔧 Восстановление конфигурации Marzban"
echo "======================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка, что Marzban запущен
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# Поиск backup файлов
echo "🔍 Поиск backup файлов..."
CONFIG_PATH="/var/lib/marzban/xray_config.json"
BACKUPS=$(docker exec anomaly-marzban ls -t /var/lib/marzban/xray_config.json.backup.* 2>/dev/null | head -5)

if [ -n "$BACKUPS" ]; then
    echo "  ✅ Найдены backup файлы:"
    echo "$BACKUPS" | while read backup; do
        echo "    - $backup"
    done
    echo ""
    
    # Использовать последний backup
    LATEST_BACKUP=$(echo "$BACKUPS" | head -1)
    echo "📋 Восстановление из: $LATEST_BACKUP"
    
    # Создать backup текущего файла
    CURRENT_BACKUP="${CONFIG_PATH}.broken.$(date +%Y%m%d_%H%M%S)"
    docker exec anomaly-marzban cp "$CONFIG_PATH" "$CURRENT_BACKUP" 2>/dev/null
    echo "  💾 Текущий файл сохранен как: $CURRENT_BACKUP"
    
    # Восстановить из backup
    docker exec anomaly-marzban cp "$LATEST_BACKUP" "$CONFIG_PATH" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  ✅ Конфигурация восстановлена из backup"
    else
        echo "  ❌ Не удалось восстановить конфигурацию"
        exit 1
    fi
else
    echo "  ⚠️  Backup файлы не найдены"
    echo "  💡 Создадим новую рабочую конфигурацию..."
    echo ""
    
    # Создать новую рабочую конфигурацию
    ./fix-xray-config-complete.sh
    exit $?
fi

echo ""
echo "🔄 Перезапуск Marzban..."
docker restart anomaly-marzban

echo ""
echo "⏳ Ожидание запуска (15 секунд)..."
sleep 15

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Проверьте статус:"
echo "   1. Логи: docker logs anomaly-marzban --tail=30"
echo "   2. Протоколы: cd /opt/Anomaly && ./check-marzban-protocols.sh"
echo "   3. Панель: https://panel.anomaly-connect.online"


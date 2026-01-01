#!/bin/bash

# Скрипт для обновления кода и исправления CONTROL_SERVER_URL на ноде

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔄 Обновление кода и исправление CONTROL_SERVER_URL"
echo "===================================================="
echo ""

# 1. Сохранить или отменить локальные изменения
echo "📦 Обработка локальных изменений..."
if [ -f fix-node-connection.sh ]; then
    echo "  Сохранение локальных изменений в stash..."
    git stash push -m "Local changes on node" fix-node-connection.sh 2>/dev/null || \
    git checkout -- fix-node-connection.sh 2>/dev/null || true
fi
echo ""

# 2. Обновить код
echo "📥 Обновление кода из репозитория..."
git pull
echo ""

# 3. Дать права на выполнение
echo "🔧 Установка прав на выполнение..."
chmod +x fix-node-control-url.sh 2>/dev/null || true
chmod +x diagnose-node-connection.sh 2>/dev/null || true
echo ""

# 4. Исправить CONTROL_SERVER_URL
echo "🔧 Исправление CONTROL_SERVER_URL..."
if [ -f .env.node ]; then
    CURRENT_URL=$(grep "^CONTROL_SERVER_URL=" .env.node | cut -d'=' -f2)
    echo "  Текущий URL: $CURRENT_URL"
    
    # Определить правильный URL
    if [ "$CURRENT_URL" = "https://api.anomaly-connect.online" ]; then
        echo ""
        echo "  ⚠️  Обнаружен неправильный URL: api.anomaly-connect.online"
        echo "  💡 Должен быть: panel.anomaly-connect.online"
        echo ""
        
        # Создать backup
        cp .env.node .env.node.backup.$(date +%Y%m%d_%H%M%S)
        echo "  ✅ Создан backup"
        
        # Исправить URL
        sed -i 's|CONTROL_SERVER_URL=.*|CONTROL_SERVER_URL=https://panel.anomaly-connect.online|' .env.node
        echo "  ✅ URL исправлен на: https://panel.anomaly-connect.online"
    else
        echo "  ✅ URL выглядит правильно: $CURRENT_URL"
    fi
    
    echo ""
    echo "  📋 Обновленный .env.node:"
    grep CONTROL_SERVER_URL .env.node
else
    echo "  ⚠️  Файл .env.node не найден"
    echo "  💡 Создайте его с правильным CONTROL_SERVER_URL"
fi
echo ""

# 5. Перезапустить marzban-node
echo "🔄 Перезапуск marzban-node..."
if docker ps | grep -q marzban-node; then
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart marzban-node 2>/dev/null || \
    systemctl restart marzban-node 2>/dev/null || \
    echo "  ⚠️  Не удалось перезапустить автоматически"
    echo "  💡 Перезапустите вручную: docker-compose -f docker-compose.node.yml restart marzban-node"
else
    echo "  ⚠️  marzban-node не запущен"
    echo "  💡 Запустите: docker-compose -f docker-compose.node.yml up -d"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Проверьте логи: docker logs marzban-node --tail=50"
echo "   3. Вернитесь в панель Marzban и нажмите 'Переподключиться'"
echo ""


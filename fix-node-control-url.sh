#!/bin/bash

# Скрипт для исправления CONTROL_SERVER_URL на ноде

echo "🔧 Исправление CONTROL_SERVER_URL на ноде"
echo "=========================================="
echo ""

# Определить Control Server URL
echo "📋 Текущий CONTROL_SERVER_URL:"
grep CONTROL_SERVER_URL .env.node 2>/dev/null || echo "  ⚠️  Не найден в .env.node"
echo ""

echo "💡 Правильный CONTROL_SERVER_URL должен указывать на панель Marzban:"
echo "   - https://panel.anomaly-connect.online"
echo "   - или IP адрес Control Server: https://YOUR_CONTROL_SERVER_IP:62050"
echo ""

# Получить IP адрес Control Server
read -p "Введите IP адрес Control Server (или нажмите Enter для использования домена): " CONTROL_IP

if [ -z "$CONTROL_IP" ]; then
    CONTROL_URL="https://panel.anomaly-connect.online"
else
    CONTROL_URL="https://${CONTROL_IP}:62050"
fi

echo ""
echo "🔄 Обновление CONTROL_SERVER_URL на: $CONTROL_URL"
echo ""

# Создать backup
if [ -f .env.node ]; then
    cp .env.node .env.node.backup.$(date +%Y%m%d_%H%M%S)
    echo "  ✅ Создан backup: .env.node.backup.*"
fi

# Обновить .env.node
if [ -f .env.node ]; then
    # Удалить старую строку CONTROL_SERVER_URL
    sed -i '/^CONTROL_SERVER_URL=/d' .env.node
    
    # Добавить новую строку
    echo "CONTROL_SERVER_URL=$CONTROL_URL" >> .env.node
    
    echo "  ✅ .env.node обновлен"
else
    echo "CONTROL_SERVER_URL=$CONTROL_URL" > .env.node
    echo "  ✅ Создан .env.node"
fi

echo ""
echo "📋 Проверка обновленного .env.node:"
grep CONTROL_SERVER_URL .env.node
echo ""

# Перезапустить marzban-node
echo "🔄 Перезапуск marzban-node..."
if docker ps | grep -q marzban-node; then
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart marzban-node 2>/dev/null || \
    systemctl restart marzban-node 2>/dev/null || \
    echo "  ⚠️  Не удалось перезапустить автоматически. Перезапустите вручную."
else
    echo "  ⚠️  marzban-node не запущен"
    echo "  💡 Запустите: docker-compose -f docker-compose.node.yml up -d"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Проверьте подключение:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Вернитесь в панель Marzban"
echo "   3. Нажмите 'Переподключиться' для ноды"
echo "   4. Проверьте логи: docker logs marzban-node --tail=50"
echo ""


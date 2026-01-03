#!/bin/bash
# Проверка логов Marzban при подключении к ноде

echo "🔍 Проверка логов Marzban при подключении к ноде"
echo "================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка последних попыток подключения к ноде..."
echo "   📋 Последние 100 строк логов (фильтр по 'node'):"
docker logs anomaly-marzban --tail 100 2>&1 | grep -i -E "(node|connecting|unable|connect)" | tail -20 | sed 's/^/      /'

echo ""
echo "2️⃣  Проверка ошибок при подключении к ноде..."
echo "   📋 Поиск ошибок и исключений:"
docker logs anomaly-marzban --tail 200 2>&1 | grep -i -E "(error|exception|traceback|failed|unable.*connect)" | tail -30 | sed 's/^/      /'

echo ""
echo "3️⃣  Проверка статуса ноды в базе данных..."
NODE_STATUS=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

with GetDB() as db:
    node = db.query(Node).filter(Node.name == 'Node 1').first()
    if node:
        print(f'Status: {node.status}')
        print(f'Message: {node.message if node.message else \"(empty)\"}')
    else:
        print('ERROR: Node 1 not found')
" 2>&1 | grep -v "UserWarning")

echo "$NODE_STATUS" | sed 's/^/   /'

echo ""
echo "4️⃣  Рекомендации:"
echo "   💡 Если Marzban подключается, но не запускает Xray:"
echo "      1. Проверьте, что конфигурация Xray валидна в панели"
echo "      2. Убедитесь, что есть хотя бы один inbound"
echo "      3. Попробуйте вручную переподключиться в панели:"
echo "         - Откройте: https://panel.anomaly-connect.online"
echo "         - Nodes -> Node 1 -> Переподключиться"
echo "      4. Проверьте логи Marzban в реальном времени:"
echo "         docker logs -f anomaly-marzban | grep -i node"
echo ""


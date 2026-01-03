#!/bin/bash
# Проверка попыток Marzban запустить Xray на ноде

echo "🔍 Проверка попыток Marzban запустить Xray на ноде"
echo "=================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка последних попыток подключения к ноде..."
echo "   📋 Поиск запросов к ноде в логах Marzban:"
docker logs anomaly-marzban --tail 500 2>&1 | grep -i -E "(node|185\.126\.67\.67|62050|connect|start|restart)" | tail -30 | sed 's/^/      /' || echo "      ℹ️  Нет запросов к ноде в последних логах"

echo ""
echo "2️⃣  Проверка ошибок при работе с нодой..."
echo "   📋 Поиск ошибок и исключений:"
docker logs anomaly-marzban --tail 500 2>&1 | grep -i -E "(error|exception|traceback|failed|connection.*aborted)" | tail -30 | sed 's/^/      /' || echo "      ℹ️  Нет ошибок в последних логах"

echo ""
echo "3️⃣  Проверка статуса ноды в базе данных..."
echo "   📋 Информация о ноде:"
docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

try:
    with GetDB() as db:
        nodes = db.query(Node).all()
        if not nodes:
            print('      ❌ Ноды не найдены в базе данных')
        else:
            for node in nodes:
                print(f'      📍 Нода: {node.name}')
                print(f'         Адрес: {node.address}')
                print(f'         Порт: {node.port}')
                print(f'         Статус: {node.status if hasattr(node, \"status\") else \"N/A\"}')
                print(f'         ID: {node.id}')
except Exception as e:
    print(f'      ❌ Ошибка: {str(e)[:200]}')
" 2>&1 | grep -v "UserWarning" | sed 's/^/      /'

echo ""
echo "4️⃣  Рекомендации:"
echo "   💡 Если Marzban не отправляет /start:"
echo "      1. Проверьте конфигурацию Xray в панели (Settings -> Xray Config)"
echo "      2. Убедитесь, что есть хотя бы один inbound (например, VMess TCP)"
echo "      3. Попробуйте вручную переподключиться в панели (Nodes -> Node 1 -> Переподключиться)"
echo "      4. Проверьте логи Marzban в реальном времени:"
echo "         docker logs -f anomaly-marzban | grep -E '(node|start|connect)'"
echo ""


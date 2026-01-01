#!/bin/bash

# Скрипт для проверки нод в базе данных Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Проверка нод в Marzban"
echo "=========================="
echo ""

# 1. Проверить, запущен ли Marzban
if ! docker-compose ps marzban | grep -q "Up"; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Проверить структуру таблицы nodes в базе данных Marzban
echo "📊 Структура таблицы nodes в Marzban:"
docker-compose exec -T marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

with GetDB() as db:
    # Получить все ноды
    nodes = db.query(Node).all()
    print(f"  Найдено нод: {len(nodes)}")
    print("")
    for node in nodes:
        print(f"  ID: {node.id}")
        print(f"  Имя: {node.name}")
        print(f"  Адрес: {getattr(node, 'address', 'N/A')}")
        print(f"  Порт: {getattr(node, 'port', 'N/A')}")
        print(f"  API порт: {getattr(node, 'api_port', 'N/A')}")
        print(f"  Статус: {getattr(node, 'status', 'N/A')}")
        print(f"  Сообщение: {getattr(node, 'message', 'N/A')}")
        print("")
PYTHON_SCRIPT

echo ""

# 3. Проверить логи Marzban
echo "📋 Логи Marzban (последние 100 строк):"
docker-compose logs marzban 2>/dev/null | tail -100 | grep -i "node\|185.126.67.67\|connection\|error\|connect" | tail -30 || echo "  Нет записей о нодах в логах"
echo ""

# 4. Проверить доступность ноды
echo "🔍 Проверка доступности ноды с Control Server:"
NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "  Тест подключения к ноде..."
RESPONSE=$(timeout 5 curl -k -s -o /dev/null -w "%{http_code}" "https://${NODE_IP}:${NODE_PORT}/ping" 2>/dev/null || echo "000")
if [ "$RESPONSE" != "000" ] && [ "$RESPONSE" != "" ]; then
    echo "    ✅ Нода доступна (HTTP код: $RESPONSE)"
else
    echo "    ⚠️  Нода недоступна по HTTPS, пробую HTTP..."
    RESPONSE=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" "http://${NODE_IP}:${NODE_PORT}/ping" 2>/dev/null || echo "000")
    if [ "$RESPONSE" != "000" ] && [ "$RESPONSE" != "" ]; then
        echo "    ✅ Нода доступна по HTTP (код: $RESPONSE)"
    else
        echo "    ❌ Нода недоступна"
    fi
fi
echo ""

echo "💡 Если нода не подключена в панели:"
echo "   1. Удалите текущую ноду в панели"
echo "   2. Создайте новую с IP адресом: 185.126.67.67"
echo "   3. Порт: 62050, API порт: 62051"
echo "   4. Нажмите 'Переподключиться'"
echo ""

echo "✅ Проверка завершена!"
echo ""


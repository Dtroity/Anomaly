#!/bin/bash

# Скрипт для исправления адреса ноды в базе данных Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление адреса ноды в Marzban"
echo "====================================="
echo ""

# 1. Проверить, запущен ли Marzban
if ! docker-compose ps marzban | grep -q "Up"; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Исправить адрес ноды в базе данных
echo "🔄 Исправление адреса ноды в базе данных..."
docker-compose exec -T marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

with GetDB() as db:
    # Найти ноду
    node = db.query(Node).filter(Node.name == "Node 1").first()
    
    if node:
        print(f"  Найдена нода: {node.name}")
        print(f"  Текущий адрес: '{node.address}' (длина: {len(node.address)})")
        
        # Удалить пробелы в начале и конце
        old_address = node.address
        node.address = node.address.strip()
        
        if old_address != node.address:
            db.commit()
            print(f"  ✅ Адрес исправлен: '{node.address}'")
        else:
            print(f"  ✅ Адрес уже правильный")
        
        print(f"  Порт: {node.port}")
        print(f"  API порт: {node.api_port}")
        print(f"  Статус: {node.status}")
        print(f"  Сообщение: {node.message}")
    else:
        print("  ❌ Нода 'Node 1' не найдена")
PYTHON_SCRIPT

echo ""

# 3. Перезапустить подключение к ноде
echo "🔄 Перезапуск подключения к ноде..."
echo "  💡 В панели Marzban нажмите 'Переподключиться' для Node 1"
echo ""

echo "✅ Готово!"
echo ""


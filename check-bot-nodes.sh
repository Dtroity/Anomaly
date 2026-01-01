#!/bin/bash

# Скрипт для проверки нод в базе данных бота

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Проверка нод в базе данных бота"
echo "==================================="
echo ""

# 1. Проверить статус бота
if ! docker ps | grep -q anomaly-bot; then
    echo "❌ Бот не запущен"
    exit 1
fi

echo "✅ Бот запущен"
echo ""

# 2. Проверить ноды в базе данных
echo "📋 Ноды в базе данных бота:"
docker exec anomaly-bot python3 << 'PYTHON_SCRIPT'
import sys
import os
sys.path.insert(0, '/app')

from sqlalchemy import create_engine, text
from config import settings

try:
    engine = create_engine(settings.database_url)
    with engine.connect() as conn:
        # Проверить таблицу nodes
        result = conn.execute(text("SELECT id, node_id, name, api_url, is_active, current_users, max_users FROM nodes"))
        nodes = result.fetchall()
        
        if nodes:
            print(f"  ✅ Найдено нод: {len(nodes)}")
            for node in nodes:
                print(f"    - ID: {node[0]}, Node ID: {node[1]}, Имя: {node[2]}")
                print(f"      API URL: {node[3]}")
                print(f"      Активна: {node[4]}, Пользователей: {node[5]}/{node[6]}")
        else:
            print("  ❌ Ноды не найдены в базе данных")
            print("  💡 Нужно добавить ноду в базу данных")
            
        # Проверить конфигурацию
        print(f"\n  📋 Конфигурация Marzban API:")
        print(f"    URL: {settings.marzban_api_url}")
        print(f"    Username: {settings.marzban_username}")
        
except Exception as e:
    print(f"  ⚠️  Ошибка: {e}")
    import traceback
    traceback.print_exc()
PYTHON_SCRIPT

echo ""

# 3. Проверить логи бота на ошибки
echo "📋 Логи бота (последние 20 строк с ошибками):"
docker-compose logs bot 2>&1 | grep -i "error\|exception\|traceback\|node" | tail -20 || echo "  Нет ошибок в логах"

echo ""
echo "✅ Проверка завершена!"
echo ""


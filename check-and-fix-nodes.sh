#!/bin/bash

# Скрипт для проверки и исправления нод

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🖥️  Проверка и исправление нод"
echo "================================"
echo ""

# 1. Проверить ноды в базе данных
echo "📊 Проверка нод в базе данных:"
docker-compose exec -T bot python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/app')
from database import get_db_context
from models import Node
from services.nodes import NodeService

try:
    with get_db_context() as db:
        # Проверить ноды в БД
        db_nodes = db.query(Node).filter(Node.is_active == True).all()
        print(f"  Найдено {len(db_nodes)} активных нод в базе данных:")
        for node in db_nodes:
            print(f"    - {node.name} (ID: {node.node_id}, URL: {node.api_url})")
        
        # Проверить доступные ноды через NodeService
        print("\n  Проверка доступных нод через NodeService:")
        node_service = NodeService(db)
        available_nodes = node_service.get_available_nodes()
        
        if available_nodes:
            print(f"    ✅ Найдено {len(available_nodes)} доступных нод:")
            for node in available_nodes:
                print(f"      - {node.get('name', 'Unknown')} (ID: {node.get('id', 'Unknown')}, Load: {node.get('load', 0):.2f})")
        else:
            print("    ❌ Нет доступных нод!")
            print("    💡 Ноды должны загружаться из конфигурации (settings.marzban_api_url)")
            
            # Попробовать добавить ноду по умолчанию
            print("\n  Попытка добавить ноду по умолчанию...")
            from config import settings
            import uuid
            from datetime import datetime
            
            default_node = Node(
                node_id=str(uuid.uuid4()),
                name="Основная нода",
                api_url=settings.marzban_api_url,
                username=settings.marzban_username,
                password=settings.marzban_password,
                is_active=True,
                max_users=0,  # Unlimited
                created_at=datetime.utcnow()
            )
            
            try:
                db.add(default_node)
                db.commit()
                print("    ✅ Нода по умолчанию добавлена в базу данных")
            except Exception as e:
                print(f"    ⚠️  Не удалось добавить ноду: {e}")
                db.rollback()
except Exception as e:
    print(f"  ❌ Ошибка: {e}")
    import traceback
    traceback.print_exc()
PYTHON_SCRIPT

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Если ноды не найдены:"
echo "   1. Убедитесь, что Marzban API доступен: curl -k https://marzban:62050/api/admin/token"
echo "   2. Добавьте ноды через панель Marzban: https://panel.anomaly-connect.online"
echo "   3. Или добавьте ноды вручную в базу данных"
echo ""


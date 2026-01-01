#!/bin/bash

# Скрипт для исправления всех проблем: ContainerConfig, пересборка бота, проверка настроек

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление всех проблем"
echo "============================"
echo ""

# 1. Удалить поврежденные контейнеры
echo "🧹 Удаление поврежденных контейнеров..."
docker ps -a | grep -E "anomaly-api|anomaly-bot" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true
docker-compose rm -f api bot 2>/dev/null || true
echo "  ✅ Контейнеры удалены"
echo ""

# 2. Обновить код
echo "📥 Обновление кода..."
git pull
echo ""

# 3. Пересобрать и запустить бота и API
echo "🔨 Пересборка бота и API..."
docker-compose build --no-cache bot api
docker-compose up -d --no-deps bot api
echo ""

# 4. Проверить статус
echo "⏳ Ожидание запуска (10 секунд)..."
sleep 10
echo ""

echo "📊 Статус контейнеров:"
docker-compose ps bot api
echo ""

# 5. Проверить логи бота
echo "📋 Логи бота (последние 20 строк):"
docker-compose logs --tail=20 bot
echo ""

# 6. Проверить настройки админа
echo "👤 Проверка настроек админа:"
echo "  Проверьте файл .env на наличие:"
echo "    - ADMIN_USERNAME"
echo "    - ADMIN_TELEGRAM_ID"
grep -E "ADMIN_USERNAME|ADMIN_TELEGRAM_ID" .env 2>/dev/null || echo "    ⚠️  Не найдено в .env"
echo ""

# 7. Проверить настройки нод в базе данных бота
echo "🖥️  Проверка настроек нод:"
echo "  Проверка нод в базе данных бота:"
docker-compose exec -T bot python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/app')
from database import get_db_context
from models import Node

try:
    with get_db_context() as db:
        nodes = db.query(Node).filter(Node.is_active == True).all()
        if nodes:
            print(f"    ✅ Найдено {len(nodes)} активных нод:")
            for node in nodes:
                print(f"      - {node.name} (ID: {node.node_id}, URL: {node.api_url})")
        else:
            print("    ⚠️  Нет активных нод в базе данных")
            print("    💡 Ноды будут загружены из конфигурации (settings.marzban_api_url)")
except Exception as e:
    print(f"    ❌ Ошибка: {e}")
PYTHON_SCRIPT
echo ""

echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Проверьте логи бота: docker-compose logs -f bot"
echo "   2. Если нет админа, создайте его через панель Marzban"
echo "   3. Если нет нод, добавьте их через панель Marzban"
echo ""


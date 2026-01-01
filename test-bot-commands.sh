#!/bin/bash

# Скрипт для проверки работы команд бота

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🧪 Тестирование команд бота"
echo "============================"
echo ""

# 1. Проверить, что бот запущен
if ! docker-compose ps bot | grep -q "Up"; then
    echo "❌ Бот не запущен"
    echo "   Запустите: docker-compose up -d bot"
    exit 1
fi
echo "✅ Бот запущен"
echo ""

# 2. Проверить логи на наличие ошибок
echo "📋 Проверка логов на ошибки (последние 100 строк):"
ERRORS=$(docker-compose logs --tail=100 bot 2>/dev/null | grep -i "error\|exception\|traceback\|failed" || echo "")
if [ -n "$ERRORS" ]; then
    echo "  ⚠️  Найдены ошибки в логах:"
    echo "$ERRORS" | head -n 20
else
    echo "  ✅ Ошибок в логах не найдено"
fi
echo ""

# 3. Проверить обработчики в коде
echo "📋 Проверка обработчиков команд:"
if grep -q "@router.message(Command(\"start\"))" vpnbot/handlers/user.py; then
    echo "  ✅ Обработчик /start найден"
else
    echo "  ❌ Обработчик /start не найден"
fi

if grep -q "@router.message(Command(\"admin\"))" vpnbot/handlers/admin.py; then
    echo "  ✅ Обработчик /admin найден"
else
    echo "  ❌ Обработчик /admin не найден"
fi
echo ""

# 4. Проверить подключение к базе данных
echo "💾 Проверка подключения к базе данных:"
DB_CHECK=$(docker-compose exec -T bot python3 -c "
import sys
sys.path.insert(0, '/app')
try:
    from database import get_db_context
    from models import User
    with get_db_context() as db:
        count = db.query(User).count()
        print(f'OK: {count} users')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null || echo "ERROR: Cannot check")

if echo "$DB_CHECK" | grep -q "OK"; then
    echo "  ✅ Подключение к БД работает: $DB_CHECK"
else
    echo "  ❌ Ошибка подключения к БД: $DB_CHECK"
fi
echo ""

# 5. Проверить подключение к Marzban API
echo "🌐 Проверка подключения к Marzban API:"
MARZBAN_CHECK=$(docker-compose exec -T bot python3 -c "
import sys
import os
sys.path.insert(0, '/app')
try:
    from config import settings
    import requests
    url = settings.marzban_api_url
    username = settings.marzban_username
    password = settings.marzban_password
    
    # Попробовать подключиться
    response = requests.get(f'{url}/api/system', auth=(username, password), timeout=5)
    if response.status_code == 200:
        print('OK: Marzban API доступен')
    else:
        print(f'ERROR: HTTP {response.status_code}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null || echo "ERROR: Cannot check")

if echo "$MARZBAN_CHECK" | grep -q "OK"; then
    echo "  ✅ Marzban API доступен"
else
    echo "  ❌ Ошибка подключения к Marzban API: $MARZBAN_CHECK"
fi
echo ""

# 6. Инструкции для тестирования
echo "📝 Инструкции для тестирования бота:"
echo ""
echo "  1. Откройте Telegram и найдите бота: @Anomaly_connectBot"
echo "  2. Отправьте команду: /start"
echo "  3. Бот должен ответить приветственным сообщением"
echo ""
echo "  Если бот не отвечает:"
echo "    - Проверьте логи: docker-compose logs -f bot"
echo "    - Перезапустите бота: docker-compose restart bot"
echo "    - Убедитесь, что бот запущен: docker-compose ps bot"
echo ""


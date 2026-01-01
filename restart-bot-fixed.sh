#!/bin/bash

# Исправленный скрипт для перезапуска бота

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔄 Перезапуск бота с новыми настройками"
echo "========================================"
echo ""

# 1. Проверить URL в .env
MARZBAN_URL=$(grep "^MARZBAN_API_URL=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
echo "📋 MARZBAN_API_URL в .env: $MARZBAN_URL"
echo ""

# 2. Проверить статус контейнеров
echo "📊 Проверка контейнеров:"
docker-compose ps | grep -E "bot|NAME" || docker ps | grep -E "bot|CONTAINER"
echo ""

# 3. Найти контейнер бота
BOT_CONTAINER=$(docker ps -a --filter "name=bot" --format "{{.Names}}" | head -n 1)
if [ -z "$BOT_CONTAINER" ]; then
    BOT_CONTAINER=$(docker ps -a --filter "name=anomaly" --format "{{.Names}}" | grep -i bot | head -n 1)
fi

if [ -z "$BOT_CONTAINER" ]; then
    echo "❌ Контейнер бота не найден"
    echo "  Удаление старых поврежденных контейнеров..."
    docker-compose rm -f bot api 2>/dev/null || true
    docker ps -a | grep -E "anomaly-bot|anomaly-api" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true
    echo "  Запуск бота через docker-compose (без зависимостей)..."
    docker-compose up -d --no-deps bot
    sleep 10
else
    echo "  Найден контейнер: $BOT_CONTAINER"
    
    # Проверить, запущен ли
    if docker ps --format "{{.Names}}" | grep -q "^${BOT_CONTAINER}$"; then
        echo "  ✅ Контейнер запущен, перезапускаю..."
        docker restart "$BOT_CONTAINER"
    else
        echo "  ⚠️  Контейнер остановлен, удаляю и пересоздаю..."
        docker rm -f "$BOT_CONTAINER" 2>/dev/null || true
        docker-compose up -d --no-deps bot
    fi
fi

echo "⏳ Ожидание запуска (10 секунд)..."
sleep 10
echo ""

# 4. Проверить статус
echo "📊 Статус контейнера:"
docker-compose ps bot 2>/dev/null || docker ps | grep bot
echo ""

# 5. Проверить переменные окружения в контейнере
echo "📋 Переменные окружения в контейнере:"
if docker-compose exec -T bot env 2>/dev/null | grep "MARZBAN_API_URL"; then
    MARZBAN_URL_IN_CONTAINER=$(docker-compose exec -T bot env 2>/dev/null | grep "MARZBAN_API_URL" | cut -d'=' -f2)
    echo "  MARZBAN_API_URL в контейнере: $MARZBAN_URL_IN_CONTAINER"
else
    echo "  ⚠️  Не удалось получить переменные окружения"
fi
echo ""

# 6. Проверить логи
echo "📋 Логи бота (последние 20 строк):"
docker-compose logs --tail=20 bot 2>/dev/null || docker logs --tail=20 "$BOT_CONTAINER" 2>/dev/null || echo "  Не удалось получить логи"
echo ""

# 7. Тест подключения (если контейнер запущен)
if docker ps --format "{{.Names}}" | grep -q "bot\|anomaly.*bot"; then
    echo "🧪 Тест подключения к Marzban API:"
    docker-compose exec -T bot python3 << 'PYTHON_SCRIPT'
import sys
import os
sys.path.insert(0, '/app')

try:
    from config import settings
    import aiohttp
    import asyncio
    
    async def test_connection():
        url = settings.marzban_api_url.rstrip('/')
        username = settings.marzban_username
        password = settings.marzban_password
        
        print(f"  URL из settings: {url}")
        print(f"  Username: {username}")
        print("")
        
        form_data = aiohttp.FormData()
        form_data.add_field('username', username)
        form_data.add_field('password', password)
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f'{url}/api/admin/token',
                    data=form_data,
                    ssl=False,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    print(f"    HTTP статус: {response.status}")
                    if response.status == 200:
                        data = await response.json()
                        token = data.get('access_token', '')
                        print(f"    ✅ Токен получен: {token[:30]}...")
                        print("    ✅ Подключение к Marzban API работает!")
                        return True
                    else:
                        text = await response.text()
                        print(f"    ❌ Ошибка: HTTP {response.status}")
                        print(f"    Ответ: {text[:200]}")
                        return False
        except Exception as e:
            print(f"    ❌ Ошибка подключения: {str(e)}")
            return False
    
    result = asyncio.run(test_connection())
    if result:
        print("")
        print("✅ Бот готов к работе!")
    else:
        print("")
        print("❌ Проблема с подключением к Marzban API")
except Exception as e:
    print(f"  ❌ Ошибка: {str(e)}")
    import traceback
    traceback.print_exc()
PYTHON_SCRIPT
else
    echo "  ⚠️  Контейнер бота не запущен, пропускаю тест"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Проверьте бота в Telegram:"
echo "   1. Откройте @Anomaly_connectBot"
echo "   2. Отправьте /start"
echo "   3. Бот должен ответить"
echo ""



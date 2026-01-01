#!/bin/bash

# Скрипт для пересоздания контейнера бота с новыми настройками

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔄 Пересоздание контейнера бота"
echo "================================"
echo ""

# 1. Проверить URL в .env
MARZBAN_URL=$(grep "^MARZBAN_API_URL=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
echo "📋 MARZBAN_API_URL в .env: $MARZBAN_URL"
echo ""

# 2. Остановить и удалить контейнер бота напрямую через docker
echo "⏸️  Остановка контейнера бота..."
docker stop anomaly-bot 2>/dev/null || true
docker rm -f anomaly-bot 2>/dev/null || true
echo "✅ Контейнер остановлен и удален"
echo ""

# 3. Пересоздать контейнер бота (используя docker-compose create и start)
echo "🚀 Пересоздание контейнера бота..."
# Сначала создаем контейнер без запуска
docker-compose create --no-deps bot 2>/dev/null || docker-compose up -d --no-deps --force-recreate bot
# Затем запускаем
docker-compose start bot 2>/dev/null || docker-compose up -d --no-deps bot
echo "⏳ Ожидание запуска (10 секунд)..."
sleep 10
echo ""

# 4. Проверить статус
echo "📊 Статус контейнера:"
docker-compose ps bot
echo ""

# 5. Проверить переменные окружения в контейнере
echo "📋 Переменные окружения в контейнере:"
MARZBAN_URL_IN_CONTAINER=$(docker-compose exec -T bot env | grep "MARZBAN_API_URL" | cut -d'=' -f2 || echo "не найдено")
echo "  MARZBAN_API_URL в контейнере: $MARZBAN_URL_IN_CONTAINER"
echo ""

# 6. Проверить логи
echo "📋 Логи бота (последние 30 строк):"
docker-compose logs --tail=30 bot
echo ""

# 7. Тест подключения
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
        
        # Тест получения токена
        print("  Тест: Получение токена аутентификации")
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
        except aiohttp.ClientConnectorError as e:
            print(f"    ❌ Ошибка подключения: {str(e)}")
            print("    Возможные причины:")
            print("      - Marzban не запущен")
            print("      - Неправильный URL или протокол")
            print("      - Проблема с Docker сетью")
            return False
        except Exception as e:
            print(f"    ❌ Ошибка: {str(e)}")
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

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Если подключение работает, проверьте бота в Telegram:"
echo "   1. Откройте @Anomaly_connectBot"
echo "   2. Отправьте /start"
echo "   3. Бот должен ответить"
echo ""


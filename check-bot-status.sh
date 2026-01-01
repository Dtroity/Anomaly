#!/bin/bash

# Скрипт для проверки статуса бота и его подключения к Marzban API

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🤖 Проверка статуса бота"
echo "=========================="
echo ""

# 1. Проверить статус контейнера бота
echo "📊 Статус контейнера бота:"
docker-compose ps bot
echo ""

# 2. Проверить переменные окружения
echo "📋 Переменные окружения бота:"
echo "  MARZBAN_API_URL:"
docker-compose exec -T bot env 2>/dev/null | grep "MARZBAN_API_URL" || echo "    ⚠️  Не найдено"
echo "  MARZBAN_USERNAME:"
docker-compose exec -T bot env 2>/dev/null | grep "MARZBAN_USERNAME" || echo "    ⚠️  Не найдено"
echo ""

# 3. Проверить логи бота
echo "📋 Логи бота (последние 30 строк):"
docker-compose logs --tail=30 bot
echo ""

# 4. Проверить подключение к Marzban API
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
        
        print(f"  URL: {url}")
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
            import traceback
            traceback.print_exc()
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
echo "💡 Проверьте бота в Telegram:"
echo "   1. Откройте @Anomaly_connectBot"
echo "   2. Отправьте /start"
echo "   3. Бот должен ответить"
echo ""


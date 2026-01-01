#!/bin/bash

# Скрипт для исправления URL Marzban API в .env

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление URL Marzban API"
echo "==============================="
echo ""

# 1. Проверить текущий URL
CURRENT_URL=$(grep "^MARZBAN_API_URL=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
echo "📋 Текущий MARZBAN_API_URL: $CURRENT_URL"
echo ""

# 2. Проверить, слушает ли Marzban на HTTPS
if docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on https://"; then
    echo "  ✅ Marzban слушает на HTTPS"
    NEW_URL="https://marzban:62050"
elif docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on http://"; then
    echo "  ⚠️  Marzban слушает на HTTP"
    NEW_URL="http://marzban:62050"
else
    echo "  ⚠️  Не удалось определить протокол Marzban"
    NEW_URL="https://marzban:62050"  # По умолчанию HTTPS
fi
echo ""

# 3. Обновить URL в .env
if [ "$CURRENT_URL" != "$NEW_URL" ]; then
    echo "🔄 Обновление MARZBAN_API_URL..."
    sed -i "s|^MARZBAN_API_URL=.*|MARZBAN_API_URL=$NEW_URL|" .env
    echo "  ✅ Обновлено: $CURRENT_URL -> $NEW_URL"
else
    echo "  ✅ URL уже правильный: $NEW_URL"
fi
echo ""

# 4. Проверить обновленный URL
UPDATED_URL=$(grep "^MARZBAN_API_URL=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
echo "📋 Обновленный MARZBAN_API_URL: $UPDATED_URL"
echo ""

# 5. Перезапустить бота
echo "🔄 Перезапуск бота..."
docker-compose restart bot
echo "⏳ Ожидание запуска (5 секунд)..."
sleep 5
echo ""

# 6. Проверить логи бота
echo "📋 Логи бота (последние 20 строк):"
docker-compose logs --tail=20 bot | grep -E "ERROR|Exception|Marzban|started" || true
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
        
        print(f"  URL: {url}")
        print(f"  Username: {username}")
        
        form_data = aiohttp.FormData()
        form_data.add_field('username', username)
        form_data.add_field('password', password)
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f'{url}/api/admin/token',
                    data=form_data,
                    ssl=False
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        print("  ✅ Подключение успешно!")
                        print(f"  Token получен: {data.get('access_token', '')[:20]}...")
                    else:
                        text = await response.text()
                        print(f"  ❌ Ошибка: HTTP {response.status}")
                        print(f"  Ответ: {text[:200]}")
        except Exception as e:
            print(f"  ❌ Ошибка подключения: {str(e)}")
    
    asyncio.run(test_connection())
except Exception as e:
    print(f"  ❌ Ошибка: {str(e)}")
PYTHON_SCRIPT

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Если подключение все еще не работает:"
echo "   1. Проверьте логи: docker-compose logs -f bot"
echo "   2. Убедитесь, что Marzban запущен: docker-compose ps marzban"
echo "   3. Проверьте учетные данные: grep MARZBAN .env"
echo ""


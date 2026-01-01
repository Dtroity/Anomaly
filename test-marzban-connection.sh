#!/bin/bash

# Детальный тест подключения к Marzban API

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🧪 Детальный тест подключения к Marzban API"
echo "============================================"
echo ""

# 1. Проверить URL в .env
MARZBAN_URL=$(grep "^MARZBAN_API_URL=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
echo "📋 MARZBAN_API_URL из .env: $MARZBAN_URL"
echo ""

# 2. Тест через curl (если доступен)
echo "🌐 Тест через curl (если доступен):"
if command -v curl &> /dev/null; then
    MARZBAN_USERNAME=$(grep "^MARZBAN_USERNAME=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    MARZBAN_PASSWORD=$(grep "^MARZBAN_PASSWORD=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    
    # Попробовать HTTP
    echo "  Попытка HTTP..."
    HTTP_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://marzban:62050/api/system" 2>/dev/null || echo "000")
    echo "    HTTP статус: $HTTP_RESULT"
    
    # Попробовать HTTPS
    echo "  Попытка HTTPS..."
    HTTPS_RESULT=$(curl -s -o /dev/null -w "%{http_code}" -k --max-time 5 "https://marzban:62050/api/system" 2>/dev/null || echo "000")
    echo "    HTTPS статус: $HTTPS_RESULT"
else
    echo "  curl не доступен"
fi
echo ""

# 3. Тест через Python из контейнера бота
echo "🧪 Тест через Python (из контейнера бота):"
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
        
        # Тест 1: Простое подключение
        print("  Тест 1: Простое подключение к /api/system")
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f'{url}/api/system',
                    ssl=False,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    print(f"    Статус: {response.status}")
                    if response.status == 401:
                        print("    ✅ Сервер отвечает (требуется аутентификация)")
                    elif response.status == 200:
                        print("    ✅ Сервер отвечает")
                    else:
                        text = await response.text()
                        print(f"    ⚠️  Неожиданный статус: {response.status}")
                        print(f"    Ответ: {text[:100]}")
        except aiohttp.ClientConnectorError as e:
            print(f"    ❌ Ошибка подключения: {str(e)}")
        except Exception as e:
            print(f"    ❌ Ошибка: {str(e)}")
        print("")
        
        # Тест 2: Получение токена
        print("  Тест 2: Получение токена аутентификации")
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
                    print(f"    Статус: {response.status}")
                    if response.status == 200:
                        data = await response.json()
                        token = data.get('access_token', '')
                        print(f"    ✅ Токен получен: {token[:30]}...")
                        print("    ✅ Подключение работает!")
                    else:
                        text = await response.text()
                        print(f"    ❌ Ошибка: HTTP {response.status}")
                        print(f"    Ответ: {text[:200]}")
        except aiohttp.ClientConnectorError as e:
            print(f"    ❌ Ошибка подключения: {str(e)}")
            print("    Возможные причины:")
            print("      - Marzban не запущен")
            print("      - Неправильный URL")
            print("      - Проблема с Docker сетью")
        except Exception as e:
            print(f"    ❌ Ошибка: {str(e)}")
    
    asyncio.run(test_connection())
except Exception as e:
    print(f"  ❌ Ошибка импорта/настройки: {str(e)}")
    import traceback
    traceback.print_exc()
PYTHON_SCRIPT

echo ""
echo "✅ Тест завершен"
echo ""


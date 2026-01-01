#!/bin/bash

# Скрипт для исправления проблемы подключения бота к Marzban API

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление подключения бота к Marzban API"
echo "============================================="
echo ""

# 1. Проверить статус Marzban
echo "📊 Статус Marzban:"
if docker-compose ps marzban | grep -q "Up"; then
    echo "  ✅ Marzban запущен"
else
    echo "  ❌ Marzban не запущен"
    echo "  Запустите: docker-compose up -d marzban"
    exit 1
fi
echo ""

# 2. Проверить доступность Marzban из контейнера бота
echo "🌐 Проверка доступности Marzban из контейнера бота:"
MARZBAN_URL=$(grep "^MARZBAN_API_URL=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
if [ -z "$MARZBAN_URL" ]; then
    echo "  ⚠️  MARZBAN_API_URL не найден в .env"
    echo "  Проверьте настройки в .env"
else
    echo "  MARZBAN_API_URL: $MARZBAN_URL"
    
    # Извлечь хост и порт
    if echo "$MARZBAN_URL" | grep -q "marzban:62050"; then
        echo "  ✅ Используется Docker network (marzban:62050)"
        
        # Проверить доступность через Docker network
        if docker-compose exec -T bot python3 -c "
import socket
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(3)
    result = sock.connect_ex(('marzban', 62050))
    sock.close()
    if result == 0:
        print('OK: Port 62050 доступен')
    else:
        print('ERROR: Port 62050 недоступен')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null; then
            echo "  ✅ Порт 62050 доступен из контейнера бота"
        else
            echo "  ❌ Порт 62050 недоступен из контейнера бота"
        fi
    else
        echo "  ⚠️  Используется внешний URL, проверка может не работать"
    fi
fi
echo ""

# 3. Проверить учетные данные Marzban
echo "📋 Проверка учетных данных Marzban:"
MARZBAN_USERNAME=$(grep "^MARZBAN_USERNAME=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
MARZBAN_PASSWORD=$(grep "^MARZBAN_PASSWORD=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)

if [ -z "$MARZBAN_USERNAME" ] || [ -z "$MARZBAN_PASSWORD" ]; then
    echo "  ❌ MARZBAN_USERNAME или MARZBAN_PASSWORD не настроены"
    echo "  Проверьте настройки в .env"
else
    echo "  ✅ Учетные данные найдены"
    echo "  Username: $MARZBAN_USERNAME"
fi
echo ""

# 4. Проверить логи Marzban
echo "📋 Логи Marzban (последние 20 строк):"
docker-compose logs --tail=20 marzban | grep -E "Uvicorn|ERROR|started|listening" || true
echo ""

# 5. Проверить, слушает ли Marzban на правильном адресе
echo "🔍 Проверка привязки Marzban:"
if docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on.*0.0.0.0:62050"; then
    echo "  ✅ Marzban слушает на 0.0.0.0:62050"
elif docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on.*127.0.0.1:62050"; then
    echo "  ❌ Marzban слушает только на 127.0.0.1:62050"
    echo "  Это проблема! Marzban должен слушать на 0.0.0.0:62050"
    echo "  Запустите: ./fix-marzban-ssl-final.sh"
else
    echo "  ⚠️  Не удалось определить привязку Marzban"
fi
echo ""

# 6. Проверить Docker сеть
echo "🌐 Проверка Docker сети:"
if docker network inspect anomaly_default 2>/dev/null | grep -q "marzban"; then
    echo "  ✅ Marzban в Docker сети"
else
    echo "  ⚠️  Marzban может быть не в Docker сети"
fi

if docker network inspect anomaly_default 2>/dev/null | grep -q "bot"; then
    echo "  ✅ Бот в Docker сети"
else
    echo "  ⚠️  Бот может быть не в Docker сети"
fi
echo ""

# 7. Тест подключения через Python
echo "🧪 Тест подключения к Marzban API:"
docker-compose exec -T bot python3 << 'PYTHON_SCRIPT'
import sys
import os
sys.path.insert(0, '/app')

try:
    from config import settings
    import requests
    from requests.auth import HTTPBasicAuth
    
    url = settings.marzban_api_url.rstrip('/')
    username = settings.marzban_username
    password = settings.marzban_password
    
    print(f"  URL: {url}")
    print(f"  Username: {username}")
    
    # Попробовать подключиться
    try:
        response = requests.get(
            f'{url}/api/system',
            auth=HTTPBasicAuth(username, password),
            timeout=10,
            verify=False
        )
        print(f"  HTTP Status: {response.status_code}")
        if response.status_code == 200:
            print("  ✅ Подключение успешно!")
        else:
            print(f"  ❌ Ошибка: HTTP {response.status_code}")
            print(f"  Ответ: {response.text[:200]}")
    except requests.exceptions.ConnectionError as e:
        print(f"  ❌ Ошибка подключения: {str(e)}")
        print("  Возможные причины:")
        print("    - Marzban не запущен")
        print("    - Неправильный URL")
        print("    - Проблема с Docker сетью")
    except Exception as e:
        print(f"  ❌ Ошибка: {str(e)}")
except Exception as e:
    print(f"  ❌ Ошибка импорта/настройки: {str(e)}")
PYTHON_SCRIPT

echo ""

# 8. Рекомендации
echo "💡 Рекомендации:"
echo ""

if ! docker-compose logs marzban 2>/dev/null | grep -q "Uvicorn running on.*0.0.0.0:62050"; then
    echo "  1. Убедитесь, что Marzban слушает на 0.0.0.0:62050"
    echo "     Запустите: ./fix-marzban-ssl-final.sh"
    echo ""
fi

echo "  2. Проверьте настройки в .env:"
echo "     MARZBAN_API_URL=http://marzban:62050"
echo "     MARZBAN_USERNAME=root"
echo "     MARZBAN_PASSWORD=your_password"
echo ""

echo "  3. Перезапустите бота после изменений:"
echo "     docker-compose restart bot"
echo ""

echo "  4. Проверьте логи бота:"
echo "     docker-compose logs -f bot"
echo ""


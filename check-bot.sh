#!/bin/bash

# Скрипт для диагностики проблем с Telegram ботом

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🤖 Диагностика Telegram бота"
echo "============================"
echo ""

# 1. Проверить статус контейнера бота
echo "📊 Статус контейнера бота:"
if docker-compose ps bot 2>/dev/null | grep -q "bot"; then
    docker-compose ps bot
else
    echo "  ❌ Контейнер бота не найден"
    echo "  Проверьте: docker-compose ps"
    exit 1
fi
echo ""

# 2. Проверить наличие BOT_TOKEN в .env
echo "📋 Проверка .env:"
if [ ! -f .env ]; then
    echo "  ❌ .env файл не найден"
    exit 1
fi

BOT_TOKEN=$(grep "^BOT_TOKEN=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
if [ -z "$BOT_TOKEN" ]; then
    echo "  ❌ BOT_TOKEN не найден в .env"
    echo "  Добавьте: BOT_TOKEN=your_bot_token"
    exit 1
else
    # Показать только первые и последние символы токена для безопасности
    TOKEN_PREVIEW="${BOT_TOKEN:0:10}...${BOT_TOKEN: -10}"
    echo "  ✅ BOT_TOKEN найден: $TOKEN_PREVIEW"
fi
echo ""

# 3. Проверить доступность бота через Telegram API
echo "🌐 Проверка доступности бота через Telegram API:"
if [ -n "$BOT_TOKEN" ]; then
    BOT_INFO=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null || echo "")
    if echo "$BOT_INFO" | grep -q '"ok":true'; then
        BOT_USERNAME=$(echo "$BOT_INFO" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
        echo "  ✅ Бот доступен: @$BOT_USERNAME"
    else
        echo "  ❌ Бот недоступен через Telegram API"
        echo "  Ответ API: $BOT_INFO"
        echo "  Проверьте правильность BOT_TOKEN"
    fi
else
    echo "  ⚠️  BOT_TOKEN пустой, пропускаю проверку API"
fi
echo ""

# 4. Проверить логи бота
echo "📋 Логи бота (последние 50 строк):"
docker-compose logs --tail=50 bot 2>/dev/null || echo "  Не удалось получить логи"
echo ""

# 5. Проверить подключение к базе данных
echo "💾 Проверка подключения к базе данных:"
if docker-compose ps db | grep -q "healthy\|Up"; then
    echo "  ✅ База данных запущена"
    
    # Проверить, может ли бот подключиться к БД
    DB_CONNECTION=$(docker-compose exec -T bot python3 -c "
import os
from sqlalchemy import create_engine
try:
    db_url = os.getenv('DATABASE_URL', '')
    if db_url:
        engine = create_engine(db_url)
        with engine.connect() as conn:
            conn.execute('SELECT 1')
        print('OK')
    else:
        print('NO_URL')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null || echo "ERROR: Cannot check")
    
    if [ "$DB_CONNECTION" = "OK" ]; then
        echo "  ✅ Бот может подключиться к базе данных"
    elif [ "$DB_CONNECTION" = "NO_URL" ]; then
        echo "  ⚠️  DATABASE_URL не настроен"
    else
        echo "  ❌ Ошибка подключения к БД: $DB_CONNECTION"
    fi
else
    echo "  ❌ База данных не запущена"
fi
echo ""

# 6. Проверить подключение к API
echo "🌐 Проверка подключения к API:"
if docker-compose ps api | grep -q "Up"; then
    echo "  ✅ API контейнер запущен"
    
    # Проверить доступность API из контейнера бота
    API_STATUS=$(docker-compose exec -T bot curl -s -o /dev/null -w "%{http_code}" http://api:8000/health 2>/dev/null || echo "000")
    if [ "$API_STATUS" = "200" ]; then
        echo "  ✅ Бот может подключиться к API"
    else
        echo "  ❌ Бот не может подключиться к API (HTTP $API_STATUS)"
    fi
else
    echo "  ❌ API контейнер не запущен"
fi
echo ""

# 7. Проверить переменные окружения бота
echo "📋 Переменные окружения бота:"
docker-compose exec -T bot env 2>/dev/null | grep -E "BOT_TOKEN|DATABASE_URL|MARZBAN|API" | head -n 10 || echo "  Не удалось получить переменные окружения"
echo ""

# 8. Проверить процессы в контейнере бота
echo "🔍 Процессы в контейнере бота:"
docker-compose exec -T bot ps aux 2>/dev/null | grep -E "python|bot" | head -n 5 || echo "  Не удалось получить процессы"
echo ""

# 9. Проверить сеть Docker
echo "🌐 Проверка Docker сети:"
if docker network inspect anomaly_default 2>/dev/null | grep -q "bot"; then
    echo "  ✅ Бот подключен к Docker сети"
else
    echo "  ⚠️  Бот может быть не подключен к Docker сети"
fi
echo ""

# 10. Рекомендации
echo "💡 Рекомендации:"
echo ""

if ! docker-compose ps bot | grep -q "Up"; then
    echo "  1. Запустите бота: docker-compose up -d bot"
fi

if [ -z "$BOT_TOKEN" ]; then
    echo "  2. Настройте BOT_TOKEN в .env файле"
fi

if ! echo "$BOT_INFO" | grep -q '"ok":true'; then
    echo "  3. Проверьте правильность BOT_TOKEN"
    echo "     Получите токен от @BotFather в Telegram"
fi

if ! docker-compose ps db | grep -q "healthy\|Up"; then
    echo "  4. Запустите базу данных: docker-compose up -d db"
fi

if ! docker-compose ps api | grep -q "Up"; then
    echo "  5. Запустите API: docker-compose up -d api"
fi

echo ""
echo "📝 Для просмотра логов в реальном времени:"
echo "   docker-compose logs -f bot"
echo ""


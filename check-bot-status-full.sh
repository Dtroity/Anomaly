#!/bin/bash

echo "🔍 Полная проверка статуса бота"
echo "================================"
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# 1. Проверка статуса контейнера
echo "📊 Проверка статуса контейнера..."
if docker ps | grep -q anomaly-bot; then
    echo "  ✅ Контейнер бота запущен"
    docker ps | grep anomaly-bot
else
    echo "  ❌ Контейнер бота не запущен"
    echo "  💡 Попробуйте: docker-compose up -d bot"
    exit 1
fi

echo ""

# 2. Проверка логов бота
echo "📋 Последние 50 строк логов бота..."
docker-compose logs --tail=50 bot 2>&1 | tail -50
echo ""

# 3. Проверка ошибок
echo "🔍 Поиск ошибок в логах..."
ERRORS=$(docker-compose logs --tail=100 bot 2>&1 | grep -i "error\|exception\|traceback\|failed\|cannot" | tail -20)
if [ -n "$ERRORS" ]; then
    echo "  ⚠️  Найдены ошибки:"
    echo "$ERRORS"
else
    echo "  ✅ Критических ошибок не найдено"
fi

echo ""

# 4. Проверка подключения к Telegram
echo "🔍 Проверка подключения к Telegram..."
TELEGRAM_LOGS=$(docker-compose logs --tail=100 bot 2>&1 | grep -i "telegram\|polling\|started\|connected" | tail -10)
if [ -n "$TELEGRAM_LOGS" ]; then
    echo "  📋 Логи подключения:"
    echo "$TELEGRAM_LOGS"
else
    echo "  ⚠️  Логи подключения к Telegram не найдены"
fi

echo ""

# 5. Проверка переменных окружения
echo "🔍 Проверка переменных окружения..."
if docker exec anomaly-bot env 2>/dev/null | grep -q "TELEGRAM_BOT_TOKEN"; then
    TOKEN_SET=$(docker exec anomaly-bot env 2>/dev/null | grep "TELEGRAM_BOT_TOKEN" | cut -d'=' -f2 | cut -c1-10)
    if [ -n "$TOKEN_SET" ] && [ "$TOKEN_SET" != "" ]; then
        echo "  ✅ TELEGRAM_BOT_TOKEN установлен (первые 10 символов: ${TOKEN_SET}...)"
    else
        echo "  ❌ TELEGRAM_BOT_TOKEN не установлен или пуст"
    fi
else
    echo "  ❌ TELEGRAM_BOT_TOKEN не найден в переменных окружения"
fi

echo ""

# 6. Проверка процесса Python
echo "🔍 Проверка процесса Python в контейнере..."
if docker exec anomaly-bot pgrep -f "python.*main.py" > /dev/null 2>&1; then
    echo "  ✅ Процесс Python запущен"
else
    echo "  ❌ Процесс Python не запущен"
    echo "  💡 Бот может быть остановлен или завершился с ошибкой"
fi

echo ""

# 7. Проверка последних сообщений в логах
echo "📋 Последние 20 строк логов (все):"
docker-compose logs --tail=20 bot 2>&1

echo ""
echo "✅ Проверка завершена!"
echo ""
echo "💡 Рекомендации:"
echo "   1. Если бот не запущен: docker-compose up -d bot"
echo "   2. Если есть ошибки, проверьте .env файл"
echo "   3. Проверьте логи в реальном времени: docker-compose logs -f bot"
echo "   4. Перезапустите бота: docker-compose restart bot"


#!/bin/bash

# Скрипт для обновления кода и проверки статуса бота

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔄 Обновление кода и проверка бота"
echo "===================================="
echo ""

# 1. Сохранить или отменить локальные изменения
echo "📦 Обработка локальных изменений..."
if [ -f restart-bot-fixed.sh ]; then
    echo "  Сохранение локальных изменений в stash..."
    git stash push -m "Local changes to restart-bot-fixed.sh" restart-bot-fixed.sh 2>/dev/null || \
    git checkout -- restart-bot-fixed.sh 2>/dev/null || true
fi
echo ""

# 2. Обновить код
echo "📥 Обновление кода из репозитория..."
git pull
echo ""

# 3. Дать права на выполнение скриптам
echo "🔧 Установка прав на выполнение..."
chmod +x check-bot-status.sh 2>/dev/null || true
chmod +x restart-bot-fixed.sh 2>/dev/null || true
chmod +x fix-docker-compose.sh 2>/dev/null || true
echo ""

# 4. Проверить статус бота
echo "🤖 Проверка статуса бота..."
if [ -f check-bot-status.sh ]; then
    ./check-bot-status.sh
else
    echo "  ⚠️  Скрипт check-bot-status.sh не найден"
    echo "  Проверка вручную..."
    
    echo ""
    echo "📊 Статус контейнера бота:"
    docker-compose ps bot
    
    echo ""
    echo "📋 Логи бота (последние 30 строк):"
    docker-compose logs --tail=30 bot
fi

echo ""
echo "✅ Готово!"


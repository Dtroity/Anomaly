#!/bin/bash

# Проверка всех сервисов Anomaly Connect

set -e

echo "🔍 Проверка всех сервисов Anomaly Connect"
echo "=========================================="
echo ""

# 1. Статус контейнеров
echo "📊 Статус контейнеров:"
docker-compose ps
echo ""

# 2. Проверка API
echo "🌐 Проверка API:"
echo -n "  Локальный: "
curl -s http://localhost/health 2>/dev/null && echo "✅" || echo "❌"

echo -n "  Внешний: "
curl -s http://api.anomaly-connect.online/health 2>/dev/null && echo "✅" || echo "❌"
echo ""

# 3. Проверка Marzban
echo "🔧 Проверка Marzban:"
echo -n "  Статус: "
if docker-compose ps marzban | grep -q "Up"; then
    echo "✅ Запущен"
else
    echo "❌ Не запущен"
fi

echo -n "  Доступность из Nginx: "
docker-compose exec -T nginx wget -qO- --timeout=5 http://marzban:62050/ 2>/dev/null | head -5 && echo "✅" || echo "❌"
echo ""

# 4. Проверка панели Marzban
echo "🎛️  Проверка панели Marzban:"
echo -n "  HTTP доступ: "
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://panel.anomaly-connect.online/ 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✅ (HTTP $RESPONSE)"
elif [ "$RESPONSE" = "502" ]; then
    echo "❌ Bad Gateway (502) - Nginx не может подключиться к Marzban"
else
    echo "⚠️  HTTP $RESPONSE"
fi
echo ""

# 5. Проверка бота
echo "🤖 Проверка бота:"
echo -n "  Статус: "
if docker-compose ps bot | grep -q "Up"; then
    echo "✅ Запущен"
else
    echo "❌ Не запущен"
fi

echo -n "  Токен: "
if grep -q "BOT_TOKEN=" .env && ! grep -q "your_telegram_bot_token" .env; then
    echo "✅ Настроен"
else
    echo "❌ Не настроен"
fi

echo -n "  Логи (последние): "
if docker-compose logs --tail=1 bot 2>/dev/null | grep -q "Run polling"; then
    echo "✅ Polling активен"
else
    echo "⚠️  Проверьте логи"
fi
echo ""

# 6. Проверка базы данных
echo "💾 Проверка базы данных:"
echo -n "  Статус: "
if docker-compose ps db | grep -q "healthy"; then
    echo "✅ Healthy"
else
    echo "⚠️  Проверьте статус"
fi
echo ""

# 7. Проверка Nginx
echo "🌐 Проверка Nginx:"
echo -n "  Статус: "
if docker-compose ps nginx | grep -q "Up"; then
    echo "✅ Запущен"
else
    echo "❌ Не запущен"
fi

echo -n "  Конфигурация: "
if [ -f nginx/conf.d/default.conf ]; then
    if grep -q "listen 443" nginx/conf.d/default.conf; then
        echo "⚠️  SSL конфигурация (сертификаты могут отсутствовать)"
    else
        echo "✅ HTTP конфигурация"
    fi
else
    echo "❌ Конфигурация не найдена"
fi
echo ""

# 8. Итоговый статус
echo "📋 Итоговый статус:"
echo "==================="
ALL_OK=true

if ! curl -s http://api.anomaly-connect.online/health > /dev/null 2>&1; then
    echo "❌ API недоступен"
    ALL_OK=false
fi

if ! docker-compose ps marzban | grep -q "Up"; then
    echo "❌ Marzban не запущен"
    ALL_OK=false
fi

if ! docker-compose ps bot | grep -q "Up"; then
    echo "❌ Bot не запущен"
    ALL_OK=false
fi

if [ "$ALL_OK" = true ]; then
    echo "✅ Все основные сервисы работают!"
    echo ""
    echo "📝 Следующие шаги:"
    echo "  1. Проверьте бота в Telegram: @Anomaly_connectBot"
    echo "  2. Настройте SSL сертификаты: ./setup-ssl.sh"
    echo "  3. Проверьте панель Marzban: http://panel.anomaly-connect.online"
else
    echo "⚠️  Есть проблемы с некоторыми сервисами"
fi

echo ""


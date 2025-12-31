#!/bin/bash

# Исправление проблемы с панелью Marzban (502 Bad Gateway)

set -e

echo "🔧 Исправление проблемы с панелью Marzban..."
echo ""

# 1. Проверить, что Marzban доступен
echo "📋 Проверка Marzban:"
docker-compose ps marzban

# 2. Проверить, что Marzban отвечает внутри Docker сети
echo ""
echo "🌐 Проверка доступности Marzban из контейнера Nginx:"
docker-compose exec nginx wget -qO- http://marzban:62050/health 2>/dev/null || echo "❌ Marzban недоступен из Nginx"

# 3. Проверить логи Marzban
echo ""
echo "📋 Логи Marzban (последние 20 строк):"
docker-compose logs --tail=20 marzban

# 4. Проверить конфигурацию Nginx для панели
echo ""
echo "📋 Проверка конфигурации Nginx для панели:"
cd nginx/conf.d
grep -A 10 "panel.anomaly-connect.online" default.conf || echo "⚠️  Конфигурация для панели не найдена"

cd ../..

# 5. Проверить, что Marzban слушает на правильном порту
echo ""
echo "🔍 Проверка портов Marzban:"
docker-compose exec marzban netstat -tlnp 2>/dev/null | grep 62050 || docker-compose exec marzban ss -tlnp | grep 62050 || echo "⚠️  Не удалось проверить порты"

# 6. Перезапустить Marzban и Nginx
echo ""
echo "🔄 Перезапуск Marzban и Nginx..."
docker-compose restart marzban
sleep 5
docker-compose restart nginx
sleep 3

# 7. Проверить доступность панели
echo ""
echo "🌐 Проверка доступности панели:"
curl -s http://panel.anomaly-connect.online/ | head -20 || echo "❌ Панель недоступна"

echo ""
echo "✅ Готово!"


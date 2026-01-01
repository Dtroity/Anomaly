#!/bin/bash

# Скрипт для проверки и исправления конфигурации ноды в Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Проверка конфигурации ноды в Marzban"
echo "========================================"
echo ""

# 1. Проверить, запущен ли Marzban
if ! docker-compose ps marzban | grep -q "Up"; then
    echo "❌ Marzban не запущен. Запустите его сначала:"
    echo "   docker-compose up -d marzban"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Проверить список нод
echo "📋 Список нод в Marzban:"
docker-compose exec -T marzban marzban-cli node list 2>/dev/null || {
    echo "  ⚠️  Не удалось получить список нод через CLI"
    echo "  💡 Проверьте в панели: https://panel.anomaly-connect.online"
}
echo ""

# 3. Проверить конфигурацию ноды в базе данных
echo "📊 Проверка конфигурации ноды в базе данных:"
docker-compose exec -T db psql -U anomaly -d anomaly << 'SQL'
SELECT id, name, address, port, api_port, status, message 
FROM nodes 
ORDER BY id;
SQL

echo ""
echo "💡 Рекомендации:"
echo ""
echo "1. В панели Marzban убедитесь, что:"
echo "   - Адрес ноды: 185.126.67.67 (IP адрес, НЕ домен)"
echo "   - Порт: 62050"
echo "   - API порт: 62051"
echo ""
echo "2. Если адрес указан как домен, измените на IP:"
echo "   - Удалите ноду"
echo "   - Создайте новую с IP адресом 185.126.67.67"
echo ""
echo "3. Проверьте, что нода доступна с Control Server:"
echo "   curl -k https://185.126.67.67:62050/ping"
echo ""

# 4. Проверить доступность ноды
echo "🔍 Проверка доступности ноды:"
NODE_IP="185.126.67.67"
NODE_PORT="62050"

if timeout 5 curl -k -s "https://${NODE_IP}:${NODE_PORT}/ping" > /dev/null 2>&1; then
    echo "  ✅ Нода доступна по HTTPS"
else
    echo "  ⚠️  Нода недоступна по HTTPS"
    echo "     Попробуйте HTTP:"
    if timeout 5 curl -k -s "http://${NODE_IP}:${NODE_PORT}/ping" > /dev/null 2>&1; then
        echo "  ✅ Нода доступна по HTTP"
    else
        echo "  ❌ Нода недоступна"
    fi
fi
echo ""

echo "✅ Проверка завершена!"
echo ""


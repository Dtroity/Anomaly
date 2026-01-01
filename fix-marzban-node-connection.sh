#!/bin/bash

# Скрипт для исправления подключения ноды в Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление подключения ноды в Marzban"
echo "=========================================="
echo ""

# 1. Проверить структуру таблицы nodes
echo "📊 Проверка структуры таблицы nodes:"
docker-compose exec -T db psql -U anomaly -d anomaly << 'SQL'
\d nodes
SQL

echo ""

# 2. Проверить текущие ноды
echo "📋 Текущие ноды в базе данных:"
docker-compose exec -T db psql -U anomaly -d anomaly << 'SQL'
SELECT id, name, port, api_port, status, message 
FROM nodes 
ORDER BY id;
SQL

echo ""

# 3. Проверить доступность ноды
echo "🔍 Проверка доступности ноды:"
NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "  Тест 1: HTTP подключение..."
HTTP_RESPONSE=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" "http://${NODE_IP}:${NODE_PORT}/ping" 2>/dev/null || echo "000")
if [ "$HTTP_RESPONSE" != "000" ] && [ "$HTTP_RESPONSE" != "" ]; then
    echo "    ✅ HTTP доступен (код: $HTTP_RESPONSE)"
else
    echo "    ❌ HTTP недоступен"
fi

echo "  Тест 2: HTTPS подключение..."
HTTPS_RESPONSE=$(timeout 5 curl -k -s -o /dev/null -w "%{http_code}" "https://${NODE_IP}:${NODE_PORT}/ping" 2>/dev/null || echo "000")
if [ "$HTTPS_RESPONSE" != "000" ] && [ "$HTTPS_RESPONSE" != "" ]; then
    echo "    ✅ HTTPS доступен (код: $HTTPS_RESPONSE)"
else
    echo "    ❌ HTTPS недоступен"
fi

echo "  Тест 3: Проверка порта..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "    ✅ Порт $NODE_PORT открыт"
else
    echo "    ❌ Порт $NODE_PORT закрыт или недоступен"
fi

echo ""

# 4. Проверить логи Marzban на ошибки подключения
echo "📋 Логи Marzban (последние 50 строк, связанные с нодами):"
docker-compose logs marzban --tail=100 | grep -i "node\|185.126.67.67\|connection\|error" | tail -20
echo ""

# 5. Рекомендации
echo "💡 Рекомендации:"
echo ""
echo "1. В панели Marzban (https://panel.anomaly-connect.online):"
echo "   - Удалите текущую ноду (Node 1)"
echo "   - Создайте новую ноду с параметрами:"
echo "     * Имя: Node 1"
echo "     * Адрес: 185.126.67.67 (IP адрес, обязательно)"
echo "     * Порт: 62050"
echo "     * API порт: 62051"
echo ""
echo "2. Убедитесь, что на ноде:"
echo "   - marzban-node запущен: docker ps | grep anomaly-node"
echo "   - Порт 62050 открыт: netstat -tlnp | grep 62050"
echo "   - CONTROL_SERVER_URL правильный: cat .env.node | grep CONTROL_SERVER_URL"
echo ""
echo "3. После создания ноды в панели:"
echo "   - Нажмите 'Переподключиться'"
echo "   - Подождите 10-20 секунд"
echo "   - Проверьте статус"
echo ""

echo "✅ Проверка завершена!"
echo ""


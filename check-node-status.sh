#!/bin/bash

# Скрипт для проверки статуса ноды

set -e

echo "🔍 Проверка статуса ноды"
echo "======================="
echo ""

cd /opt/Anomaly

# 1. Проверить статус контейнера
echo "📊 Статус контейнера:"
docker-compose -f docker-compose.node.yml ps
echo ""

# 2. Проверить логи (последние 30 строк)
echo "📋 Логи ноды (последние 30 строк):"
docker-compose -f docker-compose.node.yml logs --tail=30 marzban-node
echo ""

# 3. Проверить наличие xray_config.json
echo "📋 Проверка xray_config.json:"
if docker run --rm -v anomaly_node_data:/data alpine test -f /data/xray_config.json; then
    echo "  ✅ xray_config.json существует"
    echo "  Содержимое:"
    docker run --rm -v anomaly_node_data:/data alpine cat /data/xray_config.json | head -20
else
    echo "  ❌ xray_config.json не найден"
fi
echo ""

# 4. Проверить .env.node
echo "📋 Проверка .env.node:"
if [ -f .env.node ]; then
    echo "  ✅ .env.node существует"
    echo "  Основные параметры:"
    grep -E "CONTROL_SERVER|NODE_ID|NODE_NAME" .env.node | grep -v "^#" | grep -v "^$" || echo "  ⚠️  Параметры не найдены"
else
    echo "  ❌ .env.node не найден"
fi
echo ""

# 5. Проверить, что Xray запущен
echo "🔍 Проверка Xray:"
if docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Xray core.*started"; then
    echo "  ✅ Xray core запущен"
else
    echo "  ❌ Xray core не запущен"
fi
echo ""

# 6. Проверить порты
echo "🔍 Проверка портов:"
if docker-compose -f docker-compose.node.yml ps marzban-node | grep -q "443\|80"; then
    echo "  ✅ Порты 443 и 80 открыты"
    docker-compose -f docker-compose.node.yml ps marzban-node | grep -o "0.0.0.0:[0-9]*->[0-9]*"
else
    echo "  ⚠️  Порты не найдены"
fi
echo ""

echo "✅ Проверка завершена"
echo ""
echo "📝 Следующие шаги:"
echo "   1. Убедитесь, что .env.node правильно настроен"
echo "   2. На Control Server откройте панель Marzban"
echo "   3. Добавьте эту ноду через панель (Nodes -> Add Node)"
echo "   4. Нода автоматически подключится к Control Server"


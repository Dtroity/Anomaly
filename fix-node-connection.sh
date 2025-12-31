#!/bin/bash

# Скрипт для исправления подключения ноды к Control Server

set -e

echo "🔧 Исправление подключения ноды"
echo "================================="
echo ""

cd /opt/Anomaly

# 1. Проверить текущую конфигурацию
echo "📋 Текущая конфигурация .env.node:"
grep -E "UVICORN_HOST|UVICORN_PORT" .env.node || echo "  Параметры не найдены"
echo ""

# 2. Обновить .env.node для приема соединений
echo "🔄 Обновление .env.node..."

# Убедиться, что UVICORN_HOST=0.0.0.0
if ! grep -q "^UVICORN_HOST=0.0.0.0" .env.node; then
    sed -i '/^UVICORN_HOST=/d' .env.node
    echo "UVICORN_HOST=0.0.0.0" >> .env.node
    echo "✅ UVICORN_HOST установлен в 0.0.0.0"
else
    echo "✅ UVICORN_HOST уже установлен в 0.0.0.0"
fi

# Убедиться, что UVICORN_PORT=62050
if ! grep -q "^UVICORN_PORT=62050" .env.node; then
    sed -i '/^UVICORN_PORT=/d' .env.node
    echo "UVICORN_PORT=62050" >> .env.node
    echo "✅ UVICORN_PORT установлен в 62050"
else
    echo "✅ UVICORN_PORT уже установлен в 62050"
fi

echo ""

# 3. Проверить firewall
echo "🔥 Проверка firewall..."
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "62050"; then
        echo "✅ Порт 62050 открыт в firewall"
    else
        echo "⚠️  Порт 62050 не открыт в firewall, открываю..."
        ufw allow 62050/tcp comment "Marzban Node API"
        echo "✅ Порт 62050 открыт"
    fi
else
    echo "⚠️  UFW не установлен, проверьте firewall вручную"
fi
echo ""

# 4. Получить IP адрес ноды
echo "🌐 IP адрес ноды:"
NODE_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}' || echo "не определен")
echo "  IP: $NODE_IP"
echo ""

# 5. Перезапустить ноду
echo "🔄 Перезапуск ноды..."
docker-compose -f docker-compose.node.yml restart marzban-node

# 6. Подождать запуска
echo "⏳ Ожидание запуска ноды (15 секунд)..."
sleep 15

# 7. Проверить логи
echo ""
echo "📋 Логи ноды (последние 20 строк):"
docker-compose -f docker-compose.node.yml logs --tail=20 marzban-node | grep -E "Uvicorn running|ERROR|WARNING" || docker-compose -f docker-compose.node.yml logs --tail=20 marzban-node

# 8. Проверить, что нода слушает на 0.0.0.0
echo ""
echo "🔍 Проверка привязки:"
if docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on http://0.0.0.0:62050"; then
    echo "  ✅ Нода слушает на 0.0.0.0:62050"
elif docker-compose -f docker-compose.node.yml logs marzban-node 2>/dev/null | grep -q "Uvicorn running on http://127.0.0.1:62050"; then
    echo "  ❌ Нода все еще слушает на 127.0.0.1:62050"
    echo "  ⚠️  Нужно настроить SSL или использовать другой подход"
else
    echo "  ⚠️  Не удалось определить привязку"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "📝 Следующие шаги:"
echo "   1. IP адрес ноды: $NODE_IP"
echo "   2. На Control Server в панели Marzban:"
echo "      - Убедитесь, что Address = $NODE_IP"
echo "      - Port = 62050"
echo "      - API Port = 62051"
echo "   3. Скачайте сертификат из панели и установите на ноде (если требуется)"
echo "   4. Нажмите 'Переподключиться' в панели"


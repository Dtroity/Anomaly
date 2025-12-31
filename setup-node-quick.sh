#!/bin/bash

# Быстрая настройка ноды Anomaly VPN

set -e

echo "🚀 Настройка ноды Anomaly VPN"
echo "=============================="
echo ""

cd /opt/Anomaly

# 1. Проверить, что .env.node существует
if [ ! -f .env.node ]; then
    echo "📝 Создание .env.node из шаблона..."
    cp env.node.template .env.node
    echo "✅ Файл .env.node создан"
else
    echo "✅ Файл .env.node уже существует"
fi

echo ""
echo "📋 Содержимое .env.node:"
cat .env.node
echo ""

echo "⚠️  ВАЖНО: Нужно отредактировать .env.node и указать:"
echo "   1. CONTROL_SERVER_PASSWORD - пароль администратора Marzban с Control Server"
echo "   2. NODE_ID - уникальный ID ноды (например: node1, node2)"
echo "   3. NODE_NAME - имя ноды (например: Node 1, Node 2)"
echo ""

read -p "Нажмите Enter, чтобы открыть редактор (vi)..."
vi .env.node

echo ""
echo "✅ Файл .env.node настроен"
echo ""

# 2. Проверить Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен. Установите Docker сначала."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose не установлен. Установите docker-compose сначала."
    exit 1
fi

echo "✅ Docker и docker-compose установлены"
echo ""

# 3. Запустить ноду
echo "🚀 Запуск ноды..."
docker-compose -f docker-compose.node.yml up -d

echo ""
echo "⏳ Ожидание запуска (10 секунд)..."
sleep 10

# 4. Проверить статус
echo ""
echo "📊 Статус контейнеров:"
docker-compose -f docker-compose.node.yml ps

echo ""
echo "📋 Логи (последние 20 строк):"
docker-compose -f docker-compose.node.yml logs --tail=20

echo ""
echo "✅ Нода настроена и запущена!"
echo ""
echo "📝 Следующие шаги:"
echo "   1. Проверьте логи: docker-compose -f docker-compose.node.yml logs -f"
echo "   2. На Control Server добавьте эту ноду через панель Marzban"
echo "   3. Проверьте подключение ноды к Control Server"


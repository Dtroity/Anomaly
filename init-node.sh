#!/bin/bash

# Скрипт для инициализации xray_config.json для ноды

set -e

echo "🔧 Инициализация ноды"
echo "==================="
echo ""

cd /opt/Anomaly

# 1. Остановить ноду
echo "⏸️  Остановка ноды..."
docker-compose -f docker-compose.node.yml stop marzban-node || true
echo ""

# 2. Создать базовый xray_config.json в volume
echo "📝 Создание xray_config.json..."

XRAY_CONFIG='{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": []
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 0,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "DIRECT"
    }
  ]
}'

# Используем временный контейнер с тем же volume
docker run --rm \
  -v anomaly_node_data:/data \
  alpine sh -c "echo '$XRAY_CONFIG' > /data/xray_config.json && cat /data/xray_config.json"

echo ""
echo "✅ xray_config.json создан"
echo ""

# 3. Запустить ноду
echo "🚀 Запуск ноды..."
docker-compose -f docker-compose.node.yml up -d marzban-node

# 4. Подождать запуска
echo "⏳ Ожидание запуска ноды (15 секунд)..."
sleep 15

# 5. Проверить логи
echo ""
echo "📋 Логи ноды (последние 20 строк):"
docker-compose -f docker-compose.node.yml logs --tail=20 marzban-node

echo ""
echo "✅ Готово!"


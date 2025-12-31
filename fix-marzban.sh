#!/bin/bash

# Скрипт для исправления проблемы с Marzban (создание xray_config.json)

set -e

echo "🔧 Исправление проблемы с Marzban..."
echo ""

# Остановить Marzban
echo "⏸️  Остановка Marzban..."
docker-compose stop marzban

# Создать базовый xray_config.json в volume
echo "📝 Создание xray_config.json..."

# Создаем минимальную валидную конфигурацию с пустым inbound (Marzban требует наличие inbounds)
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
  -v anomaly_marzban_data:/data \
  alpine sh -c "echo '$XRAY_CONFIG' > /data/xray_config.json && cat /data/xray_config.json"

echo ""
echo "✅ xray_config.json создан"
echo ""

# Запустить Marzban снова
echo "🚀 Запуск Marzban..."
docker-compose up -d marzban

# Подождать немного
sleep 5

# Проверить статус
echo ""
echo "📊 Статус Marzban:"
docker-compose ps marzban

echo ""
echo "📋 Логи (последние 20 строк):"
docker-compose logs --tail=20 marzban

echo ""
echo "✅ Готово! Проверьте логи выше."


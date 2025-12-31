#!/bin/bash

# Скрипт для инициализации Marzban (создание xray_config.json)

set -e

echo "🔧 Инициализация Marzban..."

# Определяем директорию проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Создаем базовый xray_config.json для Marzban
XRAY_CONFIG='{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "BLOCK",
        "type": "field"
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "DIRECT"
    },
    {
      "protocol": "blackhole",
      "tag": "BLOCK"
    }
  ]
}'

# Создаем директорию для Marzban данных (если не существует)
mkdir -p marzban_data

# Создаем xray_config.json
echo "$XRAY_CONFIG" > marzban_data/xray_config.json

echo "✅ xray_config.json создан в marzban_data/"
echo ""
echo "⚠️  ВАЖНО: После первого запуска Marzban обновит этот файл автоматически"
echo ""


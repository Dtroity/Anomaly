#!/bin/bash

echo "🔧 Создание рабочей конфигурации Marzban"
echo "========================================"
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка статуса Marzban
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    echo "💡 Попробуйте: docker start anomaly-marzban"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# Поиск файла конфигурации
echo "🔍 Поиск файла конфигурации..."
CONFIG_PATH="/var/lib/marzban/xray_config.json"

# Проверка различных путей
CONFIG_PATHS=(
    "/var/lib/marzban/xray_config.json"
    "/var/lib/marzban/config.json"
    "/root/.local/share/marzban/xray_config.json"
)

FOUND_PATH=""
for path in "${CONFIG_PATHS[@]}"; do
    if docker exec anomaly-marzban test -f "$path" 2>/dev/null; then
        FOUND_PATH="$path"
        echo "  ✅ Найден: $FOUND_PATH"
        break
    fi
done

if [ -z "$FOUND_PATH" ]; then
    echo "  ⚠️  Файл конфигурации не найден, создадим новый"
    FOUND_PATH="$CONFIG_PATH"
else
    # Создание backup
    BACKUP_PATH="${FOUND_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    docker exec anomaly-marzban cp "$FOUND_PATH" "$BACKUP_PATH" 2>/dev/null
    echo "  💾 Backup создан: $BACKUP_PATH"
fi

# Создание рабочей конфигурации без TLS
echo ""
echo "📋 Создание рабочей конфигурации (без TLS)..."
WORKING_CONFIG='{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "API",
        "type": "field"
      }
    ]
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
    },
    {
      "tag": "VMess TCP",
      "protocol": "vmess",
      "listen": "0.0.0.0",
      "port": 443,
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "DIRECT"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "protocol": "freedom",
      "tag": "API"
    }
  ],
  "api": {
    "services": [
      "HandlerService",
      "StatsService",
      "LoggerService"
    ],
    "tag": "API"
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundDownlink": false,
      "statsInboundUplink": false,
      "statsOutboundDownlink": true,
      "statsOutboundUplink": true
    }
  }
}'

# Проверка валидности JSON
echo "🔍 Проверка валидности JSON..."
echo "$WORKING_CONFIG" | python3 -m json.tool > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  ❌ JSON невалиден!"
    exit 1
fi

echo "  ✅ JSON валиден"
echo ""

# Сохранение конфигурации
echo "💾 Сохранение конфигурации в: $FOUND_PATH"
echo "$WORKING_CONFIG" | docker exec -i anomaly-marzban sh -c "cat > $FOUND_PATH" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "  ❌ Не удалось сохранить конфигурацию"
    echo "  💡 Попробуйте создать директорию:"
    echo "     docker exec anomaly-marzban mkdir -p /var/lib/marzban"
    exit 1
fi

echo "  ✅ Конфигурация сохранена"
echo ""

# Проверка сохраненной конфигурации
echo "🔍 Проверка сохраненной конфигурации..."
sleep 2

if docker exec anomaly-marzban python3 -m json.tool "$FOUND_PATH" > /dev/null 2>&1; then
    echo "  ✅ Конфигурация валидна"
else
    echo "  ❌ Конфигурация невалидна!"
    exit 1
fi

# Проверка наличия VMess inbound
CHECK_CONFIG=$(docker exec anomaly-marzban cat "$FOUND_PATH" 2>/dev/null)
if echo "$CHECK_CONFIG" | grep -q '"tag".*"VMess TCP"'; then
    echo "  ✅ VMess inbound найден"
else
    echo "  ⚠️  VMess inbound не найден"
fi

echo ""
echo "🔄 Перезапуск Marzban..."
docker restart anomaly-marzban

echo ""
echo "⏳ Ожидание запуска (20 секунд)..."
sleep 20

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Проверьте статус:"
echo "   1. Логи: docker logs anomaly-marzban --tail=30"
echo "   2. Статус: docker ps | grep marzban"
echo "   3. Протоколы: cd /opt/Anomaly && ./check-marzban-protocols.sh"
echo ""
echo "📝 Примечание: Конфигурация создана без TLS."
echo "   Для продакшена рекомендуется добавить TLS или Reality."


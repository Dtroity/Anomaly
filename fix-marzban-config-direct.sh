#!/bin/bash

echo "🔧 Создание конфигурации Marzban через volume"
echo "=============================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Остановка Marzban
echo "⏸️  Остановка Marzban..."
docker stop anomaly-marzban 2>/dev/null
sleep 2

# Поиск volume
echo "🔍 Поиск volume Marzban..."
VOLUME_NAME=$(docker volume ls | grep marzban | grep data | awk '{print $2}' | head -1)

if [ -z "$VOLUME_NAME" ]; then
    echo "  ⚠️  Volume не найден, попробуем другой способ..."
    # Попробуем найти через inspect
    VOLUME_NAME=$(docker inspect anomaly-marzban 2>/dev/null | grep -A 5 "Mounts" | grep "Source" | head -1 | cut -d'"' -f4 | xargs basename 2>/dev/null)
fi

if [ -n "$VOLUME_NAME" ]; then
    echo "  ✅ Найден volume: $VOLUME_NAME"
    
    # Создание временного контейнера для доступа к volume
    echo ""
    echo "📋 Создание конфигурации через временный контейнер..."
    
    WORKING_CONFIG='{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": [
      {
        "inboundTag": ["api"],
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
    "services": ["HandlerService", "StatsService", "LoggerService"],
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
    
    # Создание временного контейнера
    docker run --rm -v "$VOLUME_NAME:/data" alpine sh -c "
        mkdir -p /data
        cat > /data/xray_config.json << 'EOF'
$WORKING_CONFIG
EOF
        chmod 644 /data/xray_config.json
        ls -la /data/xray_config.json
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✅ Конфигурация создана"
    else
        echo "  ⚠️  Не удалось создать через volume, попробуем другой способ..."
    fi
fi

# Альтернативный способ - через docker cp
echo ""
echo "📋 Альтернативный способ - создание через временный файл..."

TEMP_CONFIG=$(mktemp)
cat > "$TEMP_CONFIG" << 'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": [
      {
        "inboundTag": ["api"],
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
    "services": ["HandlerService", "StatsService", "LoggerService"],
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
}
EOF

# Запуск Marzban
echo "🚀 Запуск Marzban..."
docker start anomaly-marzban
sleep 5

# Попытка скопировать файл в контейнер
echo "📤 Копирование конфигурации в контейнер..."
docker cp "$TEMP_CONFIG" anomaly-marzban:/var/lib/marzban/xray_config.json 2>/dev/null

if [ $? -eq 0 ]; then
    echo "  ✅ Конфигурация скопирована"
    rm "$TEMP_CONFIG"
else
    echo "  ⚠️  Не удалось скопировать, контейнер может быть не готов"
    echo "  💡 Попробуйте вручную после запуска:"
    echo "     docker exec anomaly-marzban mkdir -p /var/lib/marzban"
    echo "     docker cp $TEMP_CONFIG anomaly-marzban:/var/lib/marzban/xray_config.json"
    rm "$TEMP_CONFIG"
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
echo "   docker logs anomaly-marzban --tail=30"
echo "   docker ps | grep marzban"


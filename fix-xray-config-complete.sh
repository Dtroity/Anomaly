#!/bin/bash

echo "🔧 Полное исправление конфигурации Xray с VMess inbound"
echo "========================================================"
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка, что Marzban запущен
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# Получение токена
echo "🔑 Получение токена..."
ADMIN_USER="Admin"
ADMIN_PASS=$(grep -E "MARZBAN_ADMIN_PASSWORD|SUDO_PASSWORD|ADMIN_PASSWORD" .env.marzban 2>/dev/null | cut -d'=' -f2 | head -1)

if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS=$(grep -E "MARZBAN_ADMIN_PASSWORD|SUDO_PASSWORD|ADMIN_PASSWORD" .env 2>/dev/null | cut -d'=' -f2 | head -1)
fi

if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS=$(docker exec anomaly-marzban env 2>/dev/null | grep -E "SUDO_PASSWORD|MARZBAN_ADMIN_PASSWORD" | cut -d'=' -f2 | head -1)
fi

if [ -z "$ADMIN_PASS" ]; then
    echo "  ⚠️  Пароль администратора не найден автоматически"
    read -sp "  Пароль администратора: " ADMIN_PASS
    echo ""
    if [ -z "$ADMIN_PASS" ]; then
        echo "  ❌ Пароль не введен"
        exit 1
    fi
fi

TOKEN_RESPONSE=$(curl -s -k -X POST "https://localhost:62050/api/admin/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" 2>/dev/null)

TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "  ❌ Не удалось получить токен"
    exit 1
fi

echo "  ✅ Токен получен"
echo ""

# Создание полной конфигурации
echo "📋 Создание полной конфигурации с VMess inbound..."
FULL_CONFIG='{
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
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/var/lib/marzban/ssl/certificate.pem",
              "keyFile": "/var/lib/marzban/ssl/key.pem"
            }
          ]
        }
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

# Сохранение конфигурации во временный файл
TEMP_CONFIG=$(mktemp)
echo "$FULL_CONFIG" > "$TEMP_CONFIG"

# Проверка валидности JSON
echo "🔍 Проверка валидности JSON..."
if ! python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "❌ JSON невалиден!"
    rm "$TEMP_CONFIG"
    exit 1
fi

echo "✅ JSON валиден"
echo ""

# Отправка конфигурации в Marzban
echo "📤 Отправка полной конфигурации в Marzban..."
RESPONSE=$(curl -s -k -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$TEMP_CONFIG" \
    https://localhost:62050/api/core/config 2>&1)

rm "$TEMP_CONFIG"

# Проверка ответа
if echo "$RESPONSE" | grep -q "detail"; then
    ERROR_MSG=$(echo "$RESPONSE" | grep -oP '"detail":\s*"\K[^"]+' || echo "$RESPONSE")
    echo "❌ Ошибка при сохранении конфигурации:"
    echo "$ERROR_MSG"
    echo ""
    echo "📋 Полный ответ:"
    echo "$RESPONSE"
    exit 1
fi

echo "✅ Конфигурация успешно сохранена!"
echo ""

# Проверка сохраненной конфигурации
echo "🔍 Проверка сохраненной конфигурации..."
sleep 3

CHECK_CONFIG=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/core/config 2>/dev/null)

if [ -z "$CHECK_CONFIG" ] || echo "$CHECK_CONFIG" | grep -q "detail"; then
    echo "⚠️ Не удалось проверить конфигурацию"
else
    # Проверка inbounds
    INBOUNDS_COUNT=$(echo "$CHECK_CONFIG" | python3 -c "import sys, json; config = json.load(sys.stdin); print(len(config.get('inbounds', [])))" 2>/dev/null || echo "0")
    echo "📋 Найдено inbounds: $INBOUNDS_COUNT"
    
    if echo "$CHECK_CONFIG" | grep -q '"tag".*"VMess TCP"'; then
        echo "✅ VMess inbound найден в конфигурации!"
    else
        echo "⚠️ VMess inbound не найден в конфигурации"
        echo "💡 Возможно, Marzban отфильтровал его. Попробуйте добавить вручную через веб-интерфейс"
    fi
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online"
echo "   2. Перейдите в раздел 'Конфигурация'"
echo "   3. Нажмите 'Перезагрузить ядро'"
echo "   4. Подождите 10-20 секунд"
echo "   5. Проверьте протоколы: cd /opt/Anomaly && ./check-marzban-protocols.sh"


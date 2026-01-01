#!/bin/bash

echo "🔧 Исправление конфигурации Xray в Marzban"
echo "=========================================="

# Проверка, что Marzban запущен
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"

# Получение токена администратора
echo ""
echo "🔑 Получение токена администратора..."
ADMIN_USER="Admin"

# Попробовать найти пароль в разных местах
ADMIN_PASS=$(grep -E "MARZBAN_ADMIN_PASSWORD|SUDO_PASSWORD|ADMIN_PASSWORD" .env 2>/dev/null | cut -d'=' -f2 | head -1)

# Если не найден, попробовать получить из переменных окружения контейнера
if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS=$(docker exec anomaly-marzban env 2>/dev/null | grep -E "SUDO_PASSWORD|MARZBAN_ADMIN_PASSWORD" | cut -d'=' -f2 | head -1)
fi

# Если все еще не найден, попросить ввести
if [ -z "$ADMIN_PASS" ]; then
    echo "  ⚠️  Пароль администратора не найден автоматически"
    echo "  💡 Попробуйте получить токен через панель или введите пароль:"
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
    echo "  Ответ: $TOKEN_RESPONSE"
    exit 1
fi

echo "  ✅ Токен получен"

# Создание полной конфигурации
echo ""
echo "📋 Создание полной конфигурации..."

# Проверка существования сертификатов
CERT_PATH="/var/lib/marzban/ssl/certificate.pem"
KEY_PATH="/var/lib/marzban/ssl/key.pem"

if ! docker exec anomaly-marzban test -f "$CERT_PATH" 2>/dev/null; then
    echo "⚠️ Сертификат не найден по пути: $CERT_PATH"
    echo "💡 Проверьте путь к сертификатам в конфигурации"
fi

# Конфигурация основана на исходной, но дополнена необходимыми секциями
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

# Отправка конфигурации в Marzban
echo ""
echo "📤 Отправка конфигурации в Marzban..."

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

# Проверка конфигурации
echo ""
echo "🔍 Проверка сохраненной конфигурации..."
sleep 2

CHECK_CONFIG=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/core/config 2>/dev/null)

if [ -z "$CHECK_CONFIG" ] || echo "$CHECK_CONFIG" | grep -q "detail"; then
    echo "⚠️ Не удалось проверить конфигурацию"
else
    # Проверка обязательных секций
    if echo "$CHECK_CONFIG" | grep -q '"inbounds"' && echo "$CHECK_CONFIG" | grep -q '"outbounds"'; then
        echo "✅ Конфигурация содержит все обязательные секции"
        
        # Подсчет inbounds
        INBOUNDS_COUNT=$(echo "$CHECK_CONFIG" | grep -o '"tag"' | wc -l || echo "0")
        echo "📋 Найдено inbounds: $INBOUNDS_COUNT"
    else
        echo "⚠️ Конфигурация может быть неполной"
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
echo "   5. Проверьте, что ошибка исчезла"


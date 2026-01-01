#!/bin/bash

# Скрипт для добавления VMess inbound в конфигурацию Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Добавление VMess inbound в конфигурацию Marzban"
echo "==================================================="
echo ""

# 1. Проверить статус Marzban
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Получить текущую конфигурацию
echo "📋 Получение текущей конфигурации..."
CONFIG_PATH="/var/lib/marzban/xray_config.json"

# Проверить, есть ли конфигурация в контейнере
if docker exec anomaly-marzban test -f "$CONFIG_PATH" 2>/dev/null; then
    echo "  ✅ Конфигурация найдена: $CONFIG_PATH"
    
    # Создать backup
    BACKUP_PATH="${CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    docker exec anomaly-marzban cp "$CONFIG_PATH" "$BACKUP_PATH" 2>/dev/null
    echo "  ✅ Создан backup: $BACKUP_PATH"
else
    echo "  ⚠️  Конфигурация не найдена в стандартном месте"
    echo "  💡 Конфигурация может храниться в volume или создаваться автоматически"
fi

echo ""
echo "💡 Инструкция по добавлению inbound:"
echo ""
echo "  В панели Marzban (https://panel.anomaly-connect.online):"
echo ""
echo "  1. Перейдите в Settings → Configuration (⚙️ Основные настройки)"
echo ""
echo "  2. Найдите массив 'inbounds' в JSON конфигурации"
echo "     (он должен быть после 'log' и 'routing')"
echo ""
echo "  3. Добавьте новый inbound в массив 'inbounds':"
echo ""
cat << 'INBOUND_CONFIG'
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
INBOUND_CONFIG

echo ""
echo "  4. Убедитесь, что массив 'inbounds' выглядит так:"
echo ""
cat << 'INBOUNDS_ARRAY'
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
]
INBOUNDS_ARRAY

echo ""
echo "  5. Нажмите 'Сохранить' (Save)"
echo ""
echo "  6. Нажмите 'Перезагрузить ядро' (Reload kernel)"
echo ""
echo "  7. Проверьте, что ошибка исчезла"
echo ""

echo "✅ Готово!"
echo ""
echo "💡 После добавления inbound:"
echo "   1. Проверьте протоколы: ./check-marzban-protocols.sh"
echo "   2. Проверьте бота в Telegram: /start → Подкл"
echo ""


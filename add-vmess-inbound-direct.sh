#!/bin/bash

echo "🔧 Добавление VMess inbound напрямую в файл конфигурации"
echo "========================================================="
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

# Поиск файла конфигурации
echo "🔍 Поиск файла конфигурации Xray..."
CONFIG_PATHS=(
    "/var/lib/marzban/xray_config.json"
    "/var/lib/marzban/config.json"
    "/root/.local/share/marzban/xray_config.json"
)

CONFIG_PATH=""
for path in "${CONFIG_PATHS[@]}"; do
    if docker exec anomaly-marzban test -f "$path" 2>/dev/null; then
        CONFIG_PATH="$path"
        echo "  ✅ Найден: $CONFIG_PATH"
        break
    fi
done

if [ -z "$CONFIG_PATH" ]; then
    echo "  ⚠️  Файл конфигурации не найден в стандартных местах"
    echo "  💡 Попробуем найти через переменные окружения..."
    
    # Попробовать найти через переменную XRAY_JSON
    XRAY_JSON=$(docker exec anomaly-marzban env 2>/dev/null | grep "XRAY_JSON" | cut -d'=' -f2)
    if [ -n "$XRAY_JSON" ] && docker exec anomaly-marzban test -f "$XRAY_JSON" 2>/dev/null; then
        CONFIG_PATH="$XRAY_JSON"
        echo "  ✅ Найден через XRAY_JSON: $CONFIG_PATH"
    else
        echo "  ❌ Не удалось найти файл конфигурации"
        echo "  💡 Попробуйте добавить inbound вручную через веб-интерфейс"
        exit 1
    fi
fi

# Создание backup
echo ""
echo "💾 Создание backup конфигурации..."
BACKUP_PATH="${CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
docker exec anomaly-marzban cp "$CONFIG_PATH" "$BACKUP_PATH" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  ✅ Backup создан: $BACKUP_PATH"
else
    echo "  ⚠️  Не удалось создать backup, продолжаем..."
fi

# Получение текущей конфигурации
echo ""
echo "📋 Получение текущей конфигурации..."
CURRENT_CONFIG=$(docker exec anomaly-marzban cat "$CONFIG_PATH" 2>/dev/null)

if [ -z "$CURRENT_CONFIG" ] || [ "$CURRENT_CONFIG" = "null" ] || [ "$(echo "$CURRENT_CONFIG" | tr -d '[:space:]')" = "" ]; then
    echo "  ⚠️  Файл конфигурации пустой или поврежден, создаем базовую конфигурацию..."
    CURRENT_CONFIG='{
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
fi

# Проверка, есть ли уже VMess inbound
if echo "$CURRENT_CONFIG" | grep -q '"tag".*"VMess TCP"'; then
    echo "  ✅ VMess inbound уже существует в конфигурации"
    exit 0
fi

# Добавление VMess inbound через Python
echo "🔧 Добавление VMess inbound..."
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | python3 << 'PYTHON_SCRIPT'
import sys
import json

try:
    # Проверка, что входные данные не пустые
    input_data = sys.stdin.read().strip()
    if not input_data or input_data == "null":
        # Создать базовую конфигурацию
        config = {
            "log": {"loglevel": "warning"},
            "routing": {"rules": []},
            "inbounds": [
                {
                    "tag": "api",
                    "listen": "127.0.0.1",
                    "port": 0,
                    "protocol": "dokodemo-door",
                    "settings": {"address": "127.0.0.1"}
                }
            ],
            "outbounds": [
                {"protocol": "freedom", "tag": "DIRECT"}
            ]
        }
    else:
        config = json.loads(input_data)
    
    # Получить существующие inbounds
    inbounds = config.get("inbounds", [])
    
    # Проверить, есть ли уже VMess inbound
    has_vmess = any(inb.get("tag") == "VMess TCP" for inb in inbounds)
    
    if has_vmess:
        print(json.dumps(config, indent=2))
        sys.exit(0)
    
    # Создать новый VMess inbound
    vmess_inbound = {
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
    
    # Добавить VMess inbound в массив
    inbounds.append(vmess_inbound)
    config["inbounds"] = inbounds
    
    # Убедиться, что есть все необходимые секции
    if "outbounds" not in config:
        config["outbounds"] = []
    
    outbound_tags = [out.get("tag") for out in config.get("outbounds", [])]
    if "blocked" not in outbound_tags:
        config["outbounds"].append({"protocol": "blackhole", "tag": "blocked"})
    if "API" not in outbound_tags:
        config["outbounds"].append({"protocol": "freedom", "tag": "API"})
    
    # Убедиться, что есть routing rules для API
    if "routing" not in config:
        config["routing"] = {"rules": []}
    
    if "rules" not in config["routing"]:
        config["routing"]["rules"] = []
    
    # Добавить routing rule для API, если её нет
    has_api_rule = any(
        isinstance(rule.get("inboundTag"), list) and 
        "api" in rule.get("inboundTag", []) and 
        rule.get("outboundTag") == "API"
        for rule in config["routing"]["rules"]
    )
    
    if not has_api_rule:
        config["routing"]["rules"].insert(0, {
            "inboundTag": ["api"],
            "outboundTag": "API",
            "type": "field"
        })
    
    # Убедиться, что есть api, stats, policy
    if "api" not in config:
        config["api"] = {
            "services": ["HandlerService", "StatsService", "LoggerService"],
            "tag": "API"
        }
    
    if "stats" not in config:
        config["stats"] = {}
    
    if "policy" not in config:
        config["policy"] = {
            "levels": {
                "0": {
                    "statsUserUplink": True,
                    "statsUserDownlink": True
                }
            },
            "system": {
                "statsInboundDownlink": False,
                "statsInboundUplink": False,
                "statsOutboundDownlink": True,
                "statsOutboundUplink": True
            }
        }
    
    print(json.dumps(config, indent=2))
    
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)

if [ $? -ne 0 ]; then
    echo "  ❌ Ошибка при обработке конфигурации"
    exit 1
fi

# Сохранение обновленной конфигурации
echo "💾 Сохранение обновленной конфигурации..."
echo "$UPDATED_CONFIG" | docker exec -i anomaly-marzban sh -c "cat > $CONFIG_PATH" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "  ❌ Не удалось сохранить конфигурацию"
    echo "  💡 Попробуйте добавить inbound вручную через веб-интерфейс"
    exit 1
fi

echo "  ✅ Конфигурация сохранена"
echo ""

# Проверка сохраненной конфигурации
echo "🔍 Проверка сохраненной конфигурации..."
sleep 2

CHECK_CONFIG=$(docker exec anomaly-marzban cat "$CONFIG_PATH" 2>/dev/null)

if echo "$CHECK_CONFIG" | grep -q '"tag".*"VMess TCP"'; then
    echo "  ✅ VMess inbound успешно добавлен!"
else
    echo "  ⚠️ VMess inbound не найден в сохраненной конфигурации"
    echo "  💡 Попробуйте добавить вручную через веб-интерфейс"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Перезапустите Marzban: docker restart anomaly-marzban"
echo "   2. Или перезагрузите ядро через панель: https://panel.anomaly-connect.online"
echo "   3. Подождите 10-20 секунд"
echo "   4. Проверьте протоколы: cd /opt/Anomaly && ./check-marzban-protocols.sh"


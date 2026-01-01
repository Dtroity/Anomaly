#!/bin/bash

echo "🔧 Добавление VMess inbound в конфигурацию Xray"
echo "==============================================="
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

# Получение текущей конфигурации
echo "📋 Получение текущей конфигурации..."
CURRENT_CONFIG=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/core/config 2>/dev/null)

if [ -z "$CURRENT_CONFIG" ] || echo "$CURRENT_CONFIG" | grep -q "detail"; then
    echo "❌ Не удалось получить конфигурацию"
    exit 1
fi

# Проверка, есть ли уже VMess inbound
if echo "$CURRENT_CONFIG" | grep -q '"tag".*"VMess TCP"'; then
    echo "✅ VMess inbound уже существует в конфигурации"
    exit 0
fi

echo "✅ Конфигурация получена"
echo ""

# Добавление VMess inbound через Python
echo "🔧 Добавление VMess inbound..."
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | python3 << 'PYTHON_SCRIPT'
import sys
import json

try:
    config = json.load(sys.stdin)
    
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
        config["outbounds"] = [
            {"protocol": "freedom", "tag": "DIRECT"},
            {"protocol": "blackhole", "tag": "blocked"},
            {"protocol": "freedom", "tag": "API"}
        ]
    else:
        # Добавить недостающие outbounds
        outbound_tags = [out.get("tag") for out in config["outbounds"]]
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
        rule.get("inboundTag") == ["api"] and rule.get("outboundTag") == "API"
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
    echo "❌ Ошибка при обработке конфигурации"
    exit 1
fi

# Сохранение обновленной конфигурации
echo "📤 Сохранение обновленной конфигурации..."
RESPONSE=$(curl -s -k -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_CONFIG" \
    https://localhost:62050/api/core/config 2>&1)

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

echo "✅ Конфигурация успешно обновлена!"
echo ""

# Проверка сохраненной конфигурации
echo "🔍 Проверка сохраненной конфигурации..."
sleep 2

CHECK_CONFIG=$(curl -s -k -H "Authorization: Bearer $TOKEN" \
    https://localhost:62050/api/core/config 2>/dev/null)

if echo "$CHECK_CONFIG" | grep -q '"tag".*"VMess TCP"'; then
    echo "✅ VMess inbound успешно добавлен!"
else
    echo "⚠️ VMess inbound не найден в сохраненной конфигурации"
    echo "💡 Возможно, Marzban отфильтровал его. Попробуйте добавить вручную через веб-интерфейс"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online"
echo "   2. Перейдите в раздел 'Конфигурация'"
echo "   3. Нажмите 'Перезагрузить ядро'"
echo "   4. Подождите 10-20 секунд"
echo "   5. Проверьте протоколы: ./check-marzban-protocols.sh"


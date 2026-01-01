#!/bin/bash

echo "🔧 Исправление проблемы с сертификатом в Marzban"
echo "================================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка статуса Marzban
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# Поиск сертификатов
echo "🔍 Поиск сертификатов..."
CERT_PATHS=(
    "/var/lib/marzban/ssl/certificate.pem"
    "/var/lib/marzban/ssl/key.pem"
    "/var/lib/marzban/ssl/cert.pem"
    "./nginx/ssl/certificate.pem"
    "./nginx/ssl/key.pem"
)

CERT_FOUND=""
KEY_FOUND=""

for path in "${CERT_PATHS[@]}"; do
    if docker exec anomaly-marzban test -f "$path" 2>/dev/null; then
        if [[ "$path" == *"certificate.pem" ]] || [[ "$path" == *"cert.pem" ]]; then
            CERT_FOUND="$path"
            echo "  ✅ Сертификат найден: $path"
        fi
        if [[ "$path" == *"key.pem" ]]; then
            KEY_FOUND="$path"
            echo "  ✅ Ключ найден: $path"
        fi
    fi
done

# Проверка на хосте
if [ -z "$CERT_FOUND" ] || [ -z "$KEY_FOUND" ]; then
    echo ""
    echo "🔍 Поиск сертификатов на хосте..."
    if [ -f "./nginx/ssl/certificate.pem" ]; then
        CERT_FOUND="./nginx/ssl/certificate.pem"
        echo "  ✅ Сертификат найден на хосте: $CERT_FOUND"
    fi
    if [ -f "./nginx/ssl/key.pem" ]; then
        KEY_FOUND="./nginx/ssl/key.pem"
        echo "  ✅ Ключ найден на хосте: $KEY_FOUND"
    fi
fi

# Если сертификаты не найдены, создадим конфигурацию без TLS
if [ -z "$CERT_FOUND" ] || [ -z "$KEY_FOUND" ]; then
    echo ""
    echo "⚠️  Сертификаты не найдены"
    echo "💡 Создадим конфигурацию без TLS (или с Reality)"
    USE_TLS=false
else
    USE_TLS=true
    # Проверка, что сертификаты доступны в контейнере
    if [[ "$CERT_FOUND" == "./"* ]]; then
        # Сертификаты на хосте, нужно проверить mount
        CERT_IN_CONTAINER="/var/lib/marzban/ssl/certificate.pem"
        if ! docker exec anomaly-marzban test -f "$CERT_IN_CONTAINER" 2>/dev/null; then
            echo ""
            echo "⚠️  Сертификаты не доступны в контейнере"
            echo "💡 Проверьте mount в docker-compose.yml"
            USE_TLS=false
        else
            CERT_FOUND="$CERT_IN_CONTAINER"
            KEY_FOUND="/var/lib/marzban/ssl/key.pem"
        fi
    fi
fi

echo ""
echo "📋 Получение текущей конфигурации..."
CONFIG_PATH="/var/lib/marzban/xray_config.json"

if ! docker exec anomaly-marzban test -f "$CONFIG_PATH" 2>/dev/null; then
    echo "  ❌ Файл конфигурации не найден"
    exit 1
fi

# Создание backup
BACKUP_PATH="${CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
docker exec anomaly-marzban cp "$CONFIG_PATH" "$BACKUP_PATH" 2>/dev/null
echo "  💾 Backup создан: $BACKUP_PATH"

# Получение текущей конфигурации
CURRENT_CONFIG=$(docker exec anomaly-marzban cat "$CONFIG_PATH" 2>/dev/null)

# Исправление конфигурации
echo ""
echo "🔧 Исправление конфигурации..."

if [ "$USE_TLS" = true ]; then
    echo "  ✅ Используем TLS с сертификатами"
    UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | python3 << PYTHON_SCRIPT
import sys
import json

try:
    config = json.loads(sys.stdin.read())
    
    # Обновить пути к сертификатам во всех inbounds
    for inbound in config.get("inbounds", []):
        if "streamSettings" in inbound and "tlsSettings" in inbound.get("streamSettings", {}):
            tls_settings = inbound["streamSettings"]["tlsSettings"]
            if "certificates" in tls_settings and len(tls_settings["certificates"]) > 0:
                cert = tls_settings["certificates"][0]
                cert["certificateFile"] = "$CERT_FOUND"
                cert["keyFile"] = "$KEY_FOUND"
    
    print(json.dumps(config, indent=2))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
else
    echo "  ⚠️  Создаем конфигурацию без TLS (только TCP)"
    UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | python3 << 'PYTHON_SCRIPT'
import sys
import json

try:
    config = json.loads(sys.stdin.read())
    
    # Удалить TLS из всех inbounds
    for inbound in config.get("inbounds", []):
        if "streamSettings" in inbound:
            stream_settings = inbound["streamSettings"]
            # Удалить security и tlsSettings
            if "security" in stream_settings:
                del stream_settings["security"]
            if "tlsSettings" in stream_settings:
                del stream_settings["tlsSettings"]
            # Если streamSettings пустой, можно оставить только network
            if not stream_settings or stream_settings == {"network": "tcp"}:
                inbound["streamSettings"] = {"network": "tcp"}
    
    print(json.dumps(config, indent=2))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
fi

if [ $? -ne 0 ]; then
    echo "  ❌ Ошибка при обработке конфигурации"
    exit 1
fi

# Сохранение исправленной конфигурации
echo "💾 Сохранение исправленной конфигурации..."
echo "$UPDATED_CONFIG" | docker exec -i anomaly-marzban sh -c "cat > $CONFIG_PATH" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "  ❌ Не удалось сохранить конфигурацию"
    exit 1
fi

echo "  ✅ Конфигурация сохранена"
echo ""

# Проверка валидности
echo "🔍 Проверка валидности JSON..."
if docker exec anomaly-marzban python3 -m json.tool "$CONFIG_PATH" > /dev/null 2>&1; then
    echo "  ✅ JSON валиден"
else
    echo "  ❌ JSON невалиден!"
    echo "  💡 Восстановление из backup..."
    docker exec anomaly-marzban cp "$BACKUP_PATH" "$CONFIG_PATH" 2>/dev/null
    exit 1
fi

echo ""
echo "🔄 Перезапуск Marzban..."
docker restart anomaly-marzban

echo ""
echo "⏳ Ожидание запуска (15 секунд)..."
sleep 15

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Проверьте статус:"
echo "   docker logs anomaly-marzban --tail=30"
echo "   docker ps | grep marzban"


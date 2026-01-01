#!/bin/bash

# Скрипт для проверки доступных протоколов в Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Проверка доступных протоколов в Marzban"
echo "==========================================="
echo ""

# 1. Проверить статус Marzban
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Получить токен
echo "🔑 Получение токена..."
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
    exit 1
fi

echo "  ✅ Токен получен"
echo ""

# 3. Получить список inbounds
echo "📋 Доступные протоколы (inbounds):"
INBOUNDS_RESPONSE=$(curl -s -k -H "Authorization: Bearer $TOKEN" https://localhost:62050/api/inbounds 2>/dev/null)

if [ -n "$INBOUNDS_RESPONSE" ] && [ "$INBOUNDS_RESPONSE" != "null" ]; then
    echo "$INBOUNDS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$INBOUNDS_RESPONSE"
    
    # Проверить, какие протоколы есть
    echo ""
    echo "📊 Анализ протоколов:"
    if echo "$INBOUNDS_RESPONSE" | grep -q "vmess"; then
        echo "  ✅ VMess доступен"
    else
        echo "  ❌ VMess недоступен"
    fi
    
    if echo "$INBOUNDS_RESPONSE" | grep -q "vless"; then
        echo "  ✅ VLESS доступен"
    else
        echo "  ❌ VLESS недоступен"
    fi
    
    if echo "$INBOUNDS_RESPONSE" | grep -q "trojan"; then
        echo "  ✅ Trojan доступен"
    else
        echo "  ❌ Trojan недоступен"
    fi
    
    if echo "$INBOUNDS_RESPONSE" | grep -q "shadowsocks"; then
        echo "  ✅ Shadowsocks доступен"
    else
        echo "  ❌ Shadowsocks недоступен"
    fi
else
    echo "  ⚠️  Не удалось получить список inbounds"
    echo "  Ответ: $INBOUNDS_RESPONSE"
fi

echo ""
echo "💡 Рекомендации:"
echo "   1. Если все протоколы недоступны, нужно настроить inbounds в панели Marzban"
echo "   2. Откройте: https://panel.anomaly-connect.online"
echo "   3. Перейдите в раздел 'Inbounds' или 'Settings'"
echo "   4. Создайте или включите хотя бы один inbound (VMess, VLESS, Trojan или Shadowsocks)"
echo ""


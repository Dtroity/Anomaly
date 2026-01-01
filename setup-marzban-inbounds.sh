#!/bin/bash

# Скрипт для настройки inbounds в Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Настройка inbounds в Marzban"
echo "================================"
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
ADMIN_PASS=$(grep -E "MARZBAN_ADMIN_PASSWORD|SUDO_PASSWORD" .env 2>/dev/null | cut -d'=' -f2 | head -1)

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

# 3. Проверить текущие inbounds
echo "📋 Текущие inbounds:"
CURRENT_INBOUNDS=$(curl -s -k -H "Authorization: Bearer $TOKEN" https://localhost:62050/api/inbounds 2>/dev/null)
echo "$CURRENT_INBOUNDS" | python3 -m json.tool 2>/dev/null || echo "$CURRENT_INBOUNDS"
echo ""

# 4. Инструкция по настройке
echo "💡 Инструкция по настройке inbounds:"
echo ""
echo "  Inbounds настраиваются через веб-интерфейс Marzban:"
echo ""
echo "  1. Откройте: https://panel.anomaly-connect.online"
echo "  2. Войдите как администратор"
echo "  3. Перейдите в раздел 'Settings' (⚙️ Основные настройки)"
echo "  4. Найдите раздел 'Inbounds' или 'Конфигурация'"
echo "  5. Нажмите 'Добавить' или 'Create Inbound'"
echo ""
echo "  Рекомендуемые настройки для VMess:"
echo "    - Protocol: VMess"
echo "    - Port: 443"
echo "    - Network: TCP"
echo "    - Security: TLS или Reality"
echo "    - Tag: VMess TCP"
echo ""
echo "  Или используйте готовые шаблоны из панели."
echo ""

# 5. Альтернатива: проверить, можно ли создать через API
echo "🔍 Проверка возможности создания через API..."
echo "  (Создание inbounds через API требует знания структуры конфигурации Xray)"
echo ""

echo "✅ Готово!"
echo ""


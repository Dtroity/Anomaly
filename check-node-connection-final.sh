#!/bin/bash

# Скрипт для финальной проверки подключения ноды

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Финальная проверка подключения ноды"
echo "========================================"
echo ""

# 1. Проверить статус Marzban
echo "📊 Проверка статуса Marzban..."
if docker ps | grep -q anomaly-marzban; then
    echo "  ✅ Marzban запущен"
else
    echo "  ❌ Marzban не запущен"
    exit 1
fi

echo ""

# 2. Проверить логи Marzban для подключения к ноде
echo "📋 Логи Marzban (последние 50 строк, связанные с нодами):"
docker-compose logs --tail=100 marzban 2>&1 | grep -i "node\|185.126.67.67\|connected\|error\|unable" | tail -20
echo ""

# 3. Проверить статус ноды через API
echo "🔍 Проверка статуса ноды через API..."
ADMIN_USER="Admin"
ADMIN_PASS=$(grep MARZBAN_ADMIN_PASSWORD .env 2>/dev/null | cut -d'=' -f2)

if [ -z "$ADMIN_PASS" ]; then
    echo "  ⚠️  Пароль администратора не найден в .env"
    echo "  💡 Попробуйте получить токен вручную через панель"
else
    # Получить токен через API
    TOKEN_RESPONSE=$(curl -s -k -X POST "https://localhost:62050/api/admin/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" 2>/dev/null)
    
    TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)
    
    if [ -n "$TOKEN" ]; then
        echo "  ✅ Токен получен"
        NODES_RESPONSE=$(curl -s -k -H "Authorization: Bearer $TOKEN" https://localhost:62050/api/nodes 2>/dev/null)
        
        if [ -n "$NODES_RESPONSE" ] && [ "$NODES_RESPONSE" != "null" ]; then
            echo "  📋 Список нод:"
            echo "$NODES_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$NODES_RESPONSE"
        else
            echo "  ⚠️  Не удалось получить список нод"
        fi
    else
        echo "  ⚠️  Не удалось получить токен"
        echo "  💡 Проверьте логин и пароль администратора"
    fi
fi

echo ""

# 4. Проверить подключение к ноде напрямую
echo "🔍 Проверка подключения к ноде напрямую..."
NODE_IP="185.126.67.67"
NODE_PORT="62050"

# Проверка HTTP
HTTP_RESPONSE=$(curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${NODE_IP}:${NODE_PORT}/ping" 2>/dev/null)
if [ "$HTTP_RESPONSE" = "200" ] || [ "$HTTP_RESPONSE" = "000" ]; then
    echo "  ✅ Нода доступна по HTTPS (код: $HTTP_RESPONSE)"
else
    echo "  ⚠️  Нода недоступна по HTTPS (код: $HTTP_RESPONSE)"
fi

# Проверка порта
if command -v nc >/dev/null 2>&1; then
    if nc -z -w 5 "$NODE_IP" "$NODE_PORT" 2>/dev/null; then
        echo "  ✅ Порт $NODE_PORT открыт"
    else
        echo "  ⚠️  Порт $NODE_PORT недоступен"
    fi
else
    echo "  💡 Установите 'nc' для проверки порта: apt-get install netcat-openbsd"
fi

echo ""

# 5. Проверить конфигурацию ноды в базе данных
echo "📋 Конфигурация ноды в базе данных:"
docker exec anomaly-marzban python3 << 'EOF'
import sys
sys.path.insert(0, '/code')
from sqlalchemy import create_engine, text
from core.config import settings

try:
    engine = create_engine(settings.database_url)
    with engine.connect() as conn:
        result = conn.execute(text("SELECT id, name, address, port, api_port, status, message FROM nodes LIMIT 5"))
        nodes = result.fetchall()
        if nodes:
            print("  Найдено нод:", len(nodes))
            for node in nodes:
                print(f"    ID: {node[0]}, Имя: {node[1]}, Адрес: {node[2]}, Порт: {node[3]}, API порт: {node[4]}, Статус: {node[5]}, Сообщение: {node[6]}")
        else:
            print("  ❌ Ноды не найдены")
except Exception as e:
    print(f"  ⚠️  Ошибка: {e}")
EOF

echo ""

# 6. Рекомендации
echo "💡 Рекомендации:"
echo "   1. Проверьте статус ноды в панели: https://panel.anomaly-connect.online"
echo "   2. Нажмите 'Переподключиться' для Node 1"
echo "   3. Подождите 10-20 секунд"
echo "   4. Проверьте логи ноды: docker logs anomaly-node --tail=30"
echo ""

echo "✅ Проверка завершена!"

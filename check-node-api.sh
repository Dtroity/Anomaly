#!/bin/bash

# Скрипт для проверки API ноды и диагностики проблемы 404

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Проверка API ноды"
echo "==================="
echo ""

# 1. Проверить статус контейнера
echo "📊 Статус контейнера:"
docker-compose -f docker-compose.node.yml ps marzban-node
echo ""

# 2. Проверить логи (последние 50 строк)
echo "📋 Логи ноды (последние 50 строк):"
docker-compose -f docker-compose.node.yml logs --tail=50 marzban-node
echo ""

# 3. Проверить открытые порты
echo "🔍 Проверка портов:"
docker-compose -f docker-compose.node.yml ps marzban-node | grep -E "62050|62051|443|80" || true
echo ""

# 4. Проверить доступность API локально
echo "🌐 Проверка доступности API:"
NODE_IP=$(hostname -I | awk '{print $1}')
echo "  IP ноды: $NODE_IP"
echo ""

# Попробовать подключиться к API
echo "  Попытка подключения к https://localhost:62050..."
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:62050/ | grep -q "200\|404\|401"; then
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:62050/)
    echo "  ✅ API отвечает (HTTP $HTTP_CODE)"
    
    # Попробовать получить ответ
    echo "  Ответ API:"
    curl -k -s https://localhost:62050/ | head -n 5 || true
else
    echo "  ❌ API не отвечает"
fi
echo ""

# 5. Проверить .env.node
echo "📋 Параметры .env.node:"
grep -E "CONTROL_SERVER|NODE_ID|UVICORN" .env.node | grep -v "^#" || true
echo ""

# 6. Проверить, что Control Server может подключиться
echo "🌐 Проверка подключения к Control Server:"
CONTROL_SERVER=$(grep "^CONTROL_SERVER=" .env.node | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")
if [ -n "$CONTROL_SERVER" ]; then
    echo "  Control Server: $CONTROL_SERVER"
    if ping -c 1 "$CONTROL_SERVER" > /dev/null 2>&1; then
        echo "  ✅ Control Server доступен (ping)"
    else
        echo "  ⚠️  Control Server недоступен (ping)"
    fi
else
    echo "  ⚠️  CONTROL_SERVER не настроен в .env.node"
fi
echo ""

# 7. Проверить firewall
echo "🔥 Проверка firewall:"
if command -v ufw &> /dev/null; then
    echo "  Статус UFW:"
    ufw status | grep -E "62050|62051" || echo "    Порты 62050/62051 не найдены в правилах"
else
    echo "  UFW не установлен"
fi
echo ""

echo "✅ Проверка завершена"
echo ""
echo "💡 Если ошибка 404:"
echo "   1. Убедитесь, что в панели Marzban для ноды указан правильный 'API порт' (обычно 62051)"
echo "   2. Проверьте, что нода правильно зарегистрирована в панели"
echo "   3. Попробуйте удалить и заново добавить ноду в панели"
echo ""


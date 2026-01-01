#!/bin/bash

echo "⏳ Ожидание запуска Marzban и проверка протоколов"
echo "=================================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Проверка, что Marzban запущен
echo "🔍 Проверка статуса Marzban..."
MAX_WAIT=60
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    if docker ps | grep -q anomaly-marzban; then
        # Проверка, что контейнер не только запущен, но и готов
        if docker exec anomaly-marzban pgrep -f "uvicorn\|marzban" > /dev/null 2>&1; then
            echo "  ✅ Marzban запущен и готов"
            break
        fi
    fi
    
    echo "  ⏳ Ожидание запуска Marzban... ($WAITED/$MAX_WAIT сек)"
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "  ⚠️  Marzban не запустился за $MAX_WAIT секунд"
    echo "  💡 Проверьте логи: docker logs anomaly-marzban --tail=50"
    exit 1
fi

# Дополнительное ожидание для полной инициализации
echo ""
echo "⏳ Ожидание полной инициализации (10 секунд)..."
sleep 10

# Запуск проверки протоколов
echo ""
echo "🔍 Проверка протоколов..."
echo ""
./check-marzban-protocols.sh


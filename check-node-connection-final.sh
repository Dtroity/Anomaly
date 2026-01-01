#!/bin/bash

# Финальная проверка подключения ноды

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Финальная проверка подключения ноды"
echo "======================================="
echo ""

# 1. Проверить логи ноды
echo "📋 Логи ноды (последние 50 строк):"
docker logs anomaly-node --tail=50 2>/dev/null || echo "  ⚠️  Не удалось получить логи"
echo ""

# 2. Проверить переменные окружения в контейнере ноды
echo "📋 Переменные окружения в контейнере ноды:"
docker exec anomaly-node env 2>/dev/null | grep -E "SSL_CLIENT_CERT_FILE|CONTROL_SERVER_URL|SERVICE_PROTOCOL" || echo "  ⚠️  Не удалось получить переменные окружения"
echo ""

# 3. Проверить сертификат в контейнере
echo "📋 Проверка сертификата в контейнере:"
if docker exec anomaly-node test -f /var/lib/marzban-node/ssl/certificate.pem 2>/dev/null; then
    echo "  ✅ Сертификат найден"
    CERT_SIZE=$(docker exec anomaly-node stat -c%s /var/lib/marzban-node/ssl/certificate.pem 2>/dev/null || echo "0")
    echo "  Размер сертификата: $CERT_SIZE байт"
    CERT_START=$(docker exec anomaly-node head -1 /var/lib/marzban-node/ssl/certificate.pem 2>/dev/null || echo "")
    if [[ "$CERT_START" == *"BEGIN CERTIFICATE"* ]]; then
        echo "  ✅ Сертификат имеет правильный формат"
    else
        echo "  ⚠️  Сертификат может иметь неправильный формат"
    fi
else
    echo "  ❌ Сертификат не найден"
fi
echo ""

# 4. Проверить логи Marzban на Control Server
echo "📋 Логи Marzban на Control Server (последние 50 строк, связанные с нодами):"
if docker-compose ps marzban 2>/dev/null | grep -q "Up"; then
    docker-compose logs marzban 2>/dev/null | tail -100 | grep -i "node\|185.126.67.67\|connected\|error\|ssl" | tail -20 || echo "  Нет записей о нодах"
else
    echo "  ⚠️  Marzban не запущен на Control Server"
fi
echo ""

# 5. Проверить статус ноды в базе данных Marzban
echo "📊 Статус ноды в базе данных Marzban:"
if docker-compose ps marzban 2>/dev/null | grep -q "Up"; then
    docker-compose exec -T marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

with GetDB() as db:
    node = db.query(Node).filter(Node.name == "Node 1").first()
    if node:
        print(f"  Имя: {node.name}")
        print(f"  Адрес: {node.address}")
        print(f"  Порт: {node.port}")
        print(f"  API порт: {node.api_port}")
        print(f"  Статус: {node.status}")
        print(f"  Сообщение: {node.message}")
    else:
        print("  ❌ Нода 'Node 1' не найдена")
PYTHON_SCRIPT
else
    echo "  ⚠️  Marzban не запущен"
fi
echo ""

echo "💡 Рекомендации:"
echo "   1. Убедитесь, что в панели Marzban нажата кнопка 'Переподключиться'"
echo "   2. Подождите 10-20 секунд после нажатия"
echo "   3. Проверьте статус в панели"
echo "   4. Если ошибка сохраняется, проверьте логи Marzban на Control Server"
echo ""

echo "✅ Проверка завершена!"
echo ""


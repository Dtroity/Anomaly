#!/bin/bash

# Детальная диагностика подключения ноды в Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Детальная диагностика подключения ноды"
echo "=========================================="
echo ""

# 1. Проверить логи Marzban с более детальной информацией
echo "📋 Детальные логи Marzban (последние 200 строк):"
docker-compose logs marzban 2>/dev/null | tail -200 | grep -A 5 -B 5 -i "node\|185.126.67.67\|connect\|error\|ssl\|certificate\|aborted\|disconnect" | tail -50
echo ""

# 2. Проверить конфигурацию ноды в базе данных
echo "📊 Детальная информация о ноде в базе данных:"
docker-compose exec -T marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

with GetDB() as db:
    node = db.query(Node).filter(Node.name == "Node 1").first()
    if node:
        print(f"  ID: {node.id}")
        print(f"  Имя: {node.name}")
        print(f"  Адрес: '{node.address}' (длина: {len(node.address)})")
        print(f"  Порт: {node.port}")
        print(f"  API порт: {node.api_port}")
        print(f"  Статус: {node.status}")
        print(f"  Сообщение: {node.message}")
        print(f"  Последнее изменение статуса: {node.last_status_change}")
PYTHON_SCRIPT

echo ""

# 3. Проверить доступность ноды с Control Server
echo "🔍 Проверка доступности ноды с Control Server:"
NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "  Тест 1: Проверка порта..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "    ✅ Порт $NODE_PORT доступен"
else
    echo "    ❌ Порт $NODE_PORT недоступен"
fi

echo "  Тест 2: HTTPS подключение (с игнорированием сертификата)..."
HTTPS_RESPONSE=$(timeout 5 curl -k -s -o /dev/null -w "%{http_code}" "https://${NODE_IP}:${NODE_PORT}/ping" 2>/dev/null || echo "000")
if [ "$HTTPS_RESPONSE" != "000" ] && [ "$HTTPS_RESPONSE" != "" ]; then
    echo "    ✅ HTTPS доступен (код: $HTTPS_RESPONSE)"
else
    echo "    ❌ HTTPS недоступен"
fi

echo "  Тест 3: Проверка SSL сертификата ноды..."
SSL_CHECK=$(timeout 5 openssl s_client -connect "${NODE_IP}:${NODE_PORT}" -servername "${NODE_IP}" </dev/null 2>/dev/null | grep -E "Verify return code" || echo "Не удалось проверить")
echo "    $SSL_CHECK"
echo ""

# 4. Проверить, как Marzban пытается подключиться
echo "💡 Анализ проблемы:"
echo ""
echo "  Ошибка: 'Connection aborted. Remote end closed connection without response'"
echo "  Это означает, что:"
echo "    1. Marzban может установить TCP соединение с нодой"
echo "    2. Но SSL/TLS handshake не завершается успешно"
echo "    3. Соединение обрывается на этапе SSL handshake"
echo ""
echo "  Возможные причины:"
echo "    1. Нода требует клиентский сертификат, но Marzban его не отправляет"
echo "    2. Сертификат ноды не соответствует ожиданиям Marzban"
echo "    3. Несовместимость SSL/TLS версий"
echo ""

# 5. Рекомендации
echo "🔧 Рекомендации для исправления:"
echo ""
echo "  1. Проверьте на ноде, что marzban-node использует правильный сертификат:"
echo "     docker exec anomaly-node cat /var/lib/marzban-node/ssl/certificate.pem | head -5"
echo ""
echo "  2. Убедитесь, что сертификат скачан из панели Marzban (не самоподписанный)"
echo ""
echo "  3. Проверьте логи marzban-node на ноде на ошибки SSL:"
echo "     docker logs anomaly-node --tail=100 | grep -i 'ssl\|certificate\|error'"
echo ""
echo "  4. Попробуйте пересоздать ноду в панели:"
echo "     - Удалите Node 1"
echo "     - Скачайте новый сертификат"
echo "     - Установите сертификат на ноде"
echo "     - Создайте новую ноду с теми же параметрами"
echo ""

echo "✅ Диагностика завершена!"
echo ""


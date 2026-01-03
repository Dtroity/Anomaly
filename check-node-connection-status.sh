#!/bin/bash
# Проверка статуса подключения к ноде и попытка переподключения

echo "🔍 Проверка статуса подключения к ноде"
echo "========================================"
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка информации о ноде в базе данных..."
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node, TLS

with GetDB() as db:
    node = db.query(Node).filter(Node.name == 'Node 1').first()
    if node:
        print(f'Node ID: {node.id}')
        print(f'Name: {node.name}')
        print(f'Address: {node.address}')
        print(f'Port: {node.port}')
        print(f'API Port: {node.api_port}')
        print(f'Status: {node.status}')
        print(f'Message: {node.message if node.message else \"(empty)\"}')
    else:
        print('ERROR: Node 1 not found')
" 2>&1)

echo "$NODE_INFO" | sed 's/^/   /'

echo ""
echo "2️⃣  Проверка последних логов Marzban о подключении к ноде..."
echo "   📋 Последние 50 строк логов:"
docker logs anomaly-marzban --tail 50 2>&1 | grep -i -E "(node|connection|tls|ssl|error|failed|185.126.67.67)" | tail -20 | sed 's/^/      /' || echo "      ℹ️  Нет записей о подключении к ноде"

echo ""
echo "3️⃣  Проверка доступности ноды по сети..."
NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "   📡 Проверка порта $NODE_PORT на $NODE_IP..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "   ✅ Порт $NODE_PORT открыт"
else
    echo "   ⚠️  Порт $NODE_PORT недоступен (может быть заблокирован файрволом)"
fi

echo ""
echo "4️⃣  Проверка TLS сертификата в базе данных..."
TLS_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

with GetDB() as db:
    tls = db.query(TLS).first()
    if tls:
        print(f'Certificate length: {len(tls.certificate) if tls.certificate else 0}')
        print(f'Key length: {len(tls.key) if tls.key else 0}')
        if tls.certificate and tls.certificate.startswith('-----BEGIN'):
            print('Certificate format: Valid PEM')
        else:
            print('Certificate format: Invalid')
    else:
        print('ERROR: TLS certificate not found')
" 2>&1)

echo "$TLS_INFO" | sed 's/^/   /'

echo ""
echo "5️⃣  Рекомендации:"
echo "   💡 Если сертификат установлен, но подключение не работает:"
echo "      1. Проверьте логи ноды на VPS #2:"
echo "         docker-compose -f docker-compose.node.yml logs marzban-node --tail 50"
echo "      2. Убедитесь, что на ноде установлен сертификат:"
echo "         ls -la /var/lib/marzban-node/ssl/"
echo "      3. Проверьте .env.node на ноде:"
echo "         cat .env.node | grep -E 'SSL|UVICORN'"
echo "      4. Попробуйте перезапустить Marzban:"
echo "         docker-compose restart marzban"
echo "      5. В панели Marzban нажмите 'Переподключиться' для Node 1"
echo ""


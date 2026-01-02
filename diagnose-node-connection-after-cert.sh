#!/bin/bash
# Диагностика подключения к ноде после установки сертификата

echo "🔍 Диагностика подключения к ноде после установки сертификата"
echo "=============================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка статуса Marzban..."
if docker ps | grep -q anomaly-marzban; then
    echo "   ✅ Marzban запущен"
    MARZBAN_STATUS=$(docker inspect anomaly-marzban --format='{{.State.Status}}')
    echo "   📊 Статус: $MARZBAN_STATUS"
else
    echo "   ❌ Marzban не запущен"
    exit 1
fi

echo ""
echo "2️⃣  Проверка TLS сертификата в базе данных..."
TLS_CHECK=$(docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    from app.db.models import TLS
    
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            print(f"SUCCESS: TLS сертификат найден")
            print(f"Certificate length: {len(tls.certificate)}")
            print(f"Key length: {len(tls.key)}")
            if tls.certificate.startswith("-----BEGIN"):
                print("Certificate format: Valid PEM")
            else:
                print("Certificate format: Invalid")
        else:
            print("ERROR: TLS сертификат не найден в базе данных")
            sys.exit(1)
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT
2>&1)

if echo "$TLS_CHECK" | grep -q "SUCCESS"; then
    echo "$TLS_CHECK" | sed 's/^/   /'
else
    echo "   ❌ $TLS_CHECK"
    exit 1
fi

echo ""
echo "3️⃣  Проверка информации о ноде в базе данных..."
NODE_CHECK=$(docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    from app.db.models import Node
    
    with GetDB() as db:
        node = db.query(Node).filter(Node.name == "Node 1").first()
        if node:
            print(f"SUCCESS: Нода найдена")
            print(f"Name: {node.name}")
            print(f"Address: {node.address}")
            print(f"Port: {node.port}")
            print(f"API Port: {node.api_port}")
            print(f"Status: {node.status}")
            print(f"Message: {node.message}")
        else:
            print("ERROR: Нода 'Node 1' не найдена")
            sys.exit(1)
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT
2>&1)

if echo "$NODE_CHECK" | grep -q "SUCCESS"; then
    echo "$NODE_CHECK" | sed 's/^/   /'
else
    echo "   ❌ $NODE_CHECK"
    exit 1
fi

echo ""
echo "4️⃣  Проверка последних логов Marzban (последние 30 строк)..."
echo "   📋 Логи подключения к ноде:"
docker logs anomaly-marzban --tail 30 2>&1 | grep -i -E "(node|connection|tls|ssl|error|failed)" | tail -10 | sed 's/^/   /' || echo "   ℹ️  Нет записей о подключении к ноде в последних логах"

echo ""
echo "5️⃣  Проверка доступности ноды по сети..."
NODE_IP=$(docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    from app.db.models import Node
    
    with GetDB() as db:
        node = db.query(Node).filter(Node.name == "Node 1").first()
        if node:
            print(node.address)
except:
    pass
PYTHON_SCRIPT
2>&1)

if [ -n "$NODE_IP" ]; then
    echo "   📡 IP ноды: $NODE_IP"
    echo "   🔍 Проверка порта 62050..."
    if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/62050" 2>/dev/null; then
        echo "   ✅ Порт 62050 открыт"
    else
        echo "   ⚠️  Порт 62050 недоступен (может быть заблокирован файрволом)"
    fi
fi

echo ""
echo "6️⃣  Рекомендации:"
echo "   💡 Если сертификат установлен, но подключение не работает:"
echo "      1. Убедитесь, что на ноде (VPS #2) запущен marzban-node:"
echo "         docker-compose -f docker-compose.node.yml ps"
echo "      2. Проверьте логи ноды:"
echo "         docker-compose -f docker-compose.node.yml logs marzban-node --tail 50"
echo "      3. Убедитесь, что на ноде установлен сертификат:"
echo "         ls -la /var/lib/marzban-node/ssl/"
echo "      4. Попробуйте перезапустить Marzban:"
echo "         docker-compose restart marzban"
echo "      5. В панели нажмите 'Переподключиться' для Node 1"
echo ""


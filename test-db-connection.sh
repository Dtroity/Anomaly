#!/bin/bash
# Тест подключения к базе данных Marzban

echo "🔍 Тест подключения к базе данных Marzban"
echo "=========================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка статуса контейнера Marzban..."
if docker ps | grep -q anomaly-marzban; then
    echo "   ✅ Контейнер запущен"
else
    echo "   ❌ Контейнер не запущен"
    exit 1
fi

echo ""
echo "2️⃣  Проверка Python в контейнере..."
PYTHON_TEST=$(docker exec anomaly-marzban python3 -c "import sys; print(f'Python {sys.version}')" 2>&1)
if [ $? -eq 0 ]; then
    echo "   ✅ Python работает: $PYTHON_TEST"
else
    echo "   ❌ Python не работает: $PYTHON_TEST"
    exit 1
fi

echo ""
echo "3️⃣  Проверка импорта модулей базы данных..."
IMPORT_TEST=$(docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    print("SUCCESS: GetDB imported")
except Exception as e:
    print(f"ERROR: GetDB import failed - {type(e).__name__}: {str(e)}")
    sys.exit(1)

try:
    from app.db.models import TLS, Node
    print("SUCCESS: TLS and Node models imported")
except Exception as e:
    print(f"ERROR: Models import failed - {type(e).__name__}: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT
2>&1)

if echo "$IMPORT_TEST" | grep -q "SUCCESS"; then
    echo "   ✅ Модули импортированы успешно"
    echo "$IMPORT_TEST" | sed 's/^/      /'
else
    echo "   ❌ Ошибка импорта:"
    echo "$IMPORT_TEST" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "4️⃣  Проверка подключения к базе данных..."
DB_TEST=$(docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    from app.db.models import TLS, Node
    
    with GetDB() as db:
        # Проверить TLS
        tls_count = db.query(TLS).count()
        print(f"TLS records: {tls_count}")
        
        if tls_count > 0:
            tls = db.query(TLS).first()
            print(f"TLS certificate length: {len(tls.certificate) if tls.certificate else 0}")
            print(f"TLS key length: {len(tls.key) if tls.key else 0}")
        
        # Проверить Nodes
        node_count = db.query(Node).count()
        print(f"Node records: {node_count}")
        
        if node_count > 0:
            nodes = db.query(Node).all()
            for node in nodes:
                print(f"  - {node.name}: {node.address}:{node.port} (status: {node.status})")
        
        print("SUCCESS: Database connection OK")
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT
2>&1)

if echo "$DB_TEST" | grep -q "SUCCESS"; then
    echo "   ✅ Подключение к базе данных успешно"
    echo "$DB_TEST" | sed 's/^/      /'
else
    echo "   ❌ Ошибка подключения к базе данных:"
    echo "$DB_TEST" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "✅ Все проверки пройдены!"
echo ""


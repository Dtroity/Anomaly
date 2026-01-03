#!/bin/bash

# Проверка генерации сертификата для ноды

echo "🔍 Проверка генерации сертификата для ноды"
echo "==========================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"

echo "1️⃣  Проверка ноды в базе данных..."
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

try:
    with GetDB() as db:
        node = db.query(Node).filter(Node.address == '$NODE_IP').first()
        if node:
            print(f\"ID: {node.id}, Name: {node.name}, Address: {node.address}, Port: {node.port}\")
        else:
            print('NOT_FOUND')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources")

if [[ "$NODE_INFO" == NOT_FOUND* ]] || [[ "$NODE_INFO" == ERROR* ]]; then
    echo "   ❌ Нода не найдена в базе данных"
    echo "   💡 Создайте ноду в панели: https://panel.anomaly-connect.online"
    exit 1
fi

echo "   ✅ Нода найдена: $NODE_INFO"
echo ""

echo "2️⃣  Проверка сертификата в базе данных..."
CERT_CHECK=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            cert_len = len(tls.certificate) if tls.certificate else 0
            key_len = len(tls.key) if tls.key else 0
            print(f\"FOUND: cert={cert_len} bytes, key={key_len} bytes\")
        else:
            print('NOT_FOUND')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources" | tail -1)

if [[ "$CERT_CHECK" == NOT_FOUND* ]]; then
    echo "   ❌ Сертификат не найден в базе данных"
    echo ""
    echo "3️⃣  Проверка логов Marzban на предмет генерации сертификата..."
    echo "   Последние логи (certificate, TLS, node):"
    docker-compose logs marzban --tail=100 | grep -i "certificate\|tls\|node" | tail -20
    echo ""
    echo "💡 Возможные причины:"
    echo "   1. Marzban генерирует сертификат только при первом подключении к ноде"
    echo "   2. Сертификат генерируется, но не сохраняется в базу данных"
    echo "   3. Нужно попробовать подключиться к ноде через панель"
    echo ""
    echo "💡 Решение:"
    echo "   1. Откройте панель: https://panel.anomaly-connect.online"
    echo "   2. Перейдите в Nodes → Node 1"
    echo "   3. Нажмите 'Переподключиться' или 'Connect'"
    echo "   4. Подождите 10-20 секунд"
    echo "   5. Затем выполните: ./fix-node-cert-direct.sh"
else
    echo "   ✅ Сертификат найден: $CERT_CHECK"
    echo ""
    echo "3️⃣  Проверка соответствия сертификата и ключа..."
    ./fix-node-cert-direct.sh
fi


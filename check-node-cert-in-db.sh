#!/bin/bash
# Проверка SSL сертификата ноды в базе данных Marzban

echo "🔍 Проверка SSL сертификата ноды в базе данных"
echo "=============================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "📋 Проверка информации о ноде в базе данных..."
NODE_INFO=$(docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node, TLS

with GetDB() as db:
    node = db.query(Node).filter(Node.name == "Node 1").first()
    if node:
        print(f"Node ID: {node.id}")
        print(f"Name: {node.name}")
        print(f"Address: {node.address}")
        print(f"Port: {node.port}")
        print(f"API Port: {node.api_port}")
        print(f"Status: {node.status}")
        print(f"Message: {node.message}")
        
        # Проверить TLS сертификаты
        tls = db.query(TLS).first()
        if tls:
            print(f"\nTLS Certificate length: {len(tls.certificate)}")
            print(f"TLS Key length: {len(tls.key)}")
            print(f"TLS Certificate preview: {tls.certificate[:100]}...")
        else:
            print("\n⚠️  TLS сертификаты не найдены в базе данных")
    else:
        print("❌ Нода 'Node 1' не найдена в базе данных")
PYTHON_SCRIPT
2>/dev/null)

if [ -n "$NODE_INFO" ]; then
    echo "$NODE_INFO" | sed 's/^/   /'
else
    echo "  ❌ Не удалось получить информацию о ноде"
fi

echo ""
echo "💡 Если TLS сертификаты отсутствуют:"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online"
echo "   2. Перейдите в Nodes -> Node 1"
echo "   3. Нажмите 'Скачать сертификат'"
echo "   4. Сертификат должен быть автоматически сохранен в базу данных"
echo "   5. Попробуйте переподключиться"
echo ""


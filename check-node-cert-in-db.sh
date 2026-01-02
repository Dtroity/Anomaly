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
import os
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    from app.db.models import Node, TLS
    
    with GetDB() as db:
        # Сначала проверить TLS
        print("=== TLS Сертификаты ===")
        tls = db.query(TLS).first()
        if tls:
            print(f"✅ TLS запись найдена")
            print(f"Certificate length: {len(tls.certificate) if tls.certificate else 0}")
            print(f"Key length: {len(tls.key) if tls.key else 0}")
            if tls.certificate and len(tls.certificate) > 0:
                print(f"Certificate preview: {tls.certificate[:100]}...")
                if tls.certificate.startswith("-----BEGIN"):
                    print("✅ TLS Certificate format: Valid PEM")
                else:
                    print("⚠️  TLS Certificate format: May be invalid")
            else:
                print("⚠️  Certificate is empty")
        else:
            print("❌ TLS сертификаты не найдены в базе данных")
            print("   💡 Нужно установить сертификат: ./fix-node-cert-in-db.sh /tmp/node-cert.pem")
        
        print("\n=== Ноды ===")
        node = db.query(Node).filter(Node.name == "Node 1").first()
        if node:
            print(f"✅ Нода 'Node 1' найдена")
            print(f"Node ID: {node.id}")
            print(f"Name: {node.name}")
            print(f"Address: {node.address}")
            print(f"Port: {node.port}")
            print(f"API Port: {node.api_port}")
            print(f"Status: {node.status}")
            print(f"Message: {node.message if node.message else '(empty)'")
        else:
            print("⚠️  Нода 'Node 1' не найдена в базе данных")
            # Попробовать найти любую ноду
            all_nodes = db.query(Node).all()
            if all_nodes:
                print(f"Найдено нод: {len(all_nodes)}")
                for n in all_nodes:
                    print(f"  - {n.name}: {n.address}:{n.port}")
            else:
                print("❌ Ноды не найдены в базе данных")
                print("   💡 Нужно добавить ноду через панель Marzban")
except ImportError as e:
    print(f"ERROR: Import error - {type(e).__name__}: {str(e)}")
    print("   💡 Возможно, проблема с путями Python или модулями")
    import traceback
    traceback.print_exc()
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {str(e)}")
    import traceback
    traceback.print_exc()
PYTHON_SCRIPT
2>&1)

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


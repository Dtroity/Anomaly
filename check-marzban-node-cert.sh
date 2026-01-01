#!/bin/bash

# Скрипт для проверки сертификата ноды в Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Проверка сертификата ноды в Marzban"
echo "======================================="
echo ""

# 1. Проверить статус Marzban
if ! docker ps | grep -q anomaly-marzban; then
    echo "❌ Marzban не запущен"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Получить сертификат ноды из базы данных
echo "📋 Информация о ноде в базе данных:"
docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node
from sqlalchemy import inspect

with GetDB() as db:
    node = db.query(Node).filter(Node.name == "Node 1").first()
    if node:
        print(f"  Имя: {node.name}")
        print(f"  Адрес: {node.address}")
        print(f"  Порт: {node.port}")
        print(f"  API порт: {node.api_port}")
        print(f"  Статус: {node.status}")
        print(f"  Сообщение: {node.message}")
        
        # Проверить все атрибуты ноды
        inspector = inspect(Node)
        columns = [col.name for col in inspector.columns]
        print(f"\n  Доступные поля в таблице nodes: {', '.join(columns)}")
        
        # Попробовать получить ssl_cert и ssl_key разными способами
        ssl_cert = None
        ssl_key = None
        
        if hasattr(node, 'ssl_cert'):
            ssl_cert = getattr(node, 'ssl_cert', None)
        if hasattr(node, 'ssl_key'):
            ssl_key = getattr(node, 'ssl_key', None)
        
        # Если не найдено, попробовать через словарь
        if not ssl_cert:
            node_dict = {col.name: getattr(node, col.name) for col in inspector.columns}
            ssl_cert = node_dict.get('ssl_cert')
            ssl_key = node_dict.get('ssl_key')
        
        print(f"\n  SSL сертификат:")
        if ssl_cert:
            cert_str = ssl_cert.decode() if isinstance(ssl_cert, bytes) else str(ssl_cert)
            cert_preview = cert_str[:200] if len(cert_str) > 200 else cert_str
            print(f"    Найден (длина: {len(cert_str)} символов)")
            print(f"    Первые 200 символов: {cert_preview}...")
        else:
            print("    ⚠️  Сертификат не найден в базе данных")
        
        print(f"\n  SSL ключ:")
        if ssl_key:
            key_str = ssl_key.decode() if isinstance(ssl_key, bytes) else str(ssl_key)
            key_preview = key_str[:200] if len(key_str) > 200 else key_str
            print(f"    Найден (длина: {len(key_str)} символов)")
            print(f"    Первые 200 символов: {key_preview}...")
        else:
            print("    ⚠️  Ключ не найден в базе данных")
    else:
        print("  ❌ Нода не найдена")
        # Показать все ноды
        all_nodes = db.query(Node).all()
        if all_nodes:
            print(f"\n  Найдено нод: {len(all_nodes)}")
            for n in all_nodes:
                print(f"    - {n.name} ({n.address}:{n.port})")
PYTHON_SCRIPT

echo ""

# 3. Проверить, как Marzban пытается подключиться
echo "💡 Важная информация:"
echo ""
echo "  Marzban использует клиентский сертификат для подключения к ноде."
echo "  Этот сертификат должен быть:"
echo "    1. Скачан из панели Marzban при создании ноды"
echo "    2. Установлен на ноде как SSL_CLIENT_CERT_FILE"
echo "    3. Нода должна принимать этот клиентский сертификат"
echo ""
echo "  Проблема может быть в том, что:"
echo "    - Сертификат в базе данных Marzban не совпадает с сертификатом на ноде"
echo "    - Нода не настроена для приема клиентских сертификатов"
echo "    - Сертификат устарел или недействителен"
echo ""

# 4. Рекомендации
echo "🔧 Рекомендации:"
echo ""
echo "  1. Пересоздайте ноду в панели Marzban:"
echo "     - Удалите Node 1"
echo "     - Создайте новую ноду с теми же параметрами"
echo "     - Скачайте новый сертификат"
echo ""
echo "  2. Установите сертификат на ноде:"
echo "     - Скопируйте сертификат в /var/lib/marzban-node/ssl/certificate.pem"
echo "     - Убедитесь, что SSL_CLIENT_CERT_FILE указывает на правильный путь"
echo ""
echo "  3. Проверьте, что сертификат совпадает:"
echo "     - Сравните сертификат из панели с сертификатом на ноде"
echo ""

echo "✅ Проверка завершена!"


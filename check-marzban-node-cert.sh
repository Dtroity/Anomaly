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

# 2. Получить сертификат из таблицы TLS
echo "📋 Сертификат для подключения к нодам (из таблицы TLS):"
docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
try:
    from app.db import GetDB
    from app.db.models import TLS
    
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            print(f"  ✅ Сертификат найден в таблице TLS")
            print(f"  Сертификат (первые 200 символов):")
            cert_preview = tls.certificate[:200] if len(tls.certificate) > 200 else tls.certificate
            print(f"    {cert_preview}...")
            print(f"  Ключ (первые 200 символов):")
            key_preview = tls.key[:200] if len(tls.key) > 200 else tls.key
            print(f"    {key_preview}...")
            print(f"\n  💡 Этот сертификат используется Marzban для подключения ко всем нодам")
            print(f"  💡 Он должен быть установлен на ноде как SSL_CLIENT_CERT_FILE")
        else:
            print("  ❌ Сертификат не найден в таблице TLS")
            print("  💡 Таблица TLS пуста. Нужно сгенерировать сертификат в панели Marzban")
except Exception as e:
    print(f"  ⚠️  Ошибка при получении сертификата: {e}")
    import traceback
    traceback.print_exc()
PYTHON_SCRIPT

echo ""

# 3. Получить информацию о ноде
echo "📋 Информация о ноде в базе данных:"
docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
import sys
sys.path.insert(0, '/code')
try:
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
    else:
        print("  ❌ Нода 'Node 1' не найдена")
        # Показать все ноды
        all_nodes = db.query(Node).all()
        if all_nodes:
            print(f"\n  Найдено нод: {len(all_nodes)}")
            for n in all_nodes:
                print(f"    - {n.name} ({n.address}:{n.port})")
        else:
            print("  ⚠️  Ноды не найдены в базе данных")
except Exception as e:
    print(f"  ⚠️  Ошибка при получении информации о ноде: {e}")
    import traceback
    traceback.print_exc()
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


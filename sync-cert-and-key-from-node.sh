#!/bin/bash
# Синхронизация сертификата И ключа с ноды в базу данных Marzban

echo "🔄 Синхронизация сертификата и ключа с ноды в базу данных"
echo "=========================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

CERT_FILE="/tmp/node-cert-from-node.pem"
KEY_FILE="/tmp/node-key-from-node.pem"

echo "1️⃣  Проверка наличия ключа на ноде..."
echo "   📋 Проверка файлов на ноде:"
NODE_CHECK=$(ssh root@185.126.67.67 "docker exec anomaly-node ls -la /var/lib/marzban-node/ssl/ 2>&1" 2>&1 | grep -v "password:")

if echo "$NODE_CHECK" | grep -q "key.pem\|private.key"; then
    echo "   ✅ Ключ найден на ноде"
    echo "$NODE_CHECK" | sed 's/^/      /'
    
    echo ""
    echo "2️⃣  Копирование сертификата и ключа с ноды..."
    scp root@185.126.67.67:/var/lib/marzban-node/ssl/certificate.pem "$CERT_FILE" 2>&1 | grep -v "password:"
    scp root@185.126.67.67:/var/lib/marzban-node/ssl/key.pem "$KEY_FILE" 2>&1 | grep -v "password:"
    
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "   ✅ Сертификат и ключ скопированы"
    else
        echo "   ❌ Не удалось скопировать файлы"
        exit 1
    fi
else
    echo "   ⚠️  Ключ не найден на ноде"
    echo "$NODE_CHECK" | sed 's/^/      /'
    echo ""
    echo "   💡 Ключ может быть в другом месте или не сохранен на ноде"
    echo "   📋 Проверка переменных окружения на ноде:"
    ssh root@185.126.67.67 "docker exec anomaly-node env | grep -i key" 2>&1 | grep -v "password:" | sed 's/^/      /'
    
    echo ""
    echo "   💡 Решение: Перегенерируйте сертификат в панели Marzban"
    echo "      1. Откройте: https://panel.anomaly-connect.online"
    echo "      2. Перейдите в Nodes -> Node 1"
    echo "      3. Удалите ноду и создайте заново"
    echo "      4. Или скачайте новый сертификат и установите на ноду"
    exit 1
fi

echo ""
echo "3️⃣  Установка сертификата и ключа в базу данных Marzban..."
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "   📋 Обновление базы данных:"
    docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with open('$CERT_FILE', 'r') as f:
        cert = f.read()
    
    with open('$KEY_FILE', 'r') as f:
        key = f.read()
    
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            tls.certificate = cert
            tls.key = key
            db.commit()
            print('SUCCESS: Certificate and key updated in database')
            print(f'Certificate length: {len(cert)}')
            print(f'Key length: {len(key)}')
        else:
            print('ERROR: TLS record not found in database')
            sys.exit(1)
            
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | grep -v "UserWarning" | sed 's/^/      /'
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "4️⃣  Перезапуск Marzban для применения изменений..."
        docker-compose restart marzban
        echo "   ⏳ Ожидание 10 секунд..."
        sleep 10
        
        echo ""
        echo "✅ Готово!"
        echo ""
        echo "💡 Следующие шаги:"
        echo "   1. Подождите 10-20 секунд"
        echo "   2. Откройте панель: https://panel.anomaly-connect.online"
        echo "   3. Перейдите в Nodes -> Node 1"
        echo "   4. Нажмите 'Переподключиться'"
        echo "   5. Проверьте статус ноды"
        echo ""
    else
        echo "   ❌ Ошибка при обновлении базы данных"
        exit 1
    fi
else
    echo "   ❌ Файлы сертификата или ключа не найдены"
    exit 1
fi


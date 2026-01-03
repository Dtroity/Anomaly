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

echo "1️⃣  Определение путей к сертификату и ключу на ноде..."
echo "   📋 Проверка переменных окружения на ноде:"
KEY_PATH=$(ssh root@185.126.67.67 "docker exec anomaly-node env | grep UVICORN_SSL_KEYFILE" 2>&1 | grep -v "password:" | cut -d'=' -f2)

if [ -z "$KEY_PATH" ]; then
    echo "   ⚠️  UVICORN_SSL_KEYFILE не найден, проверяю стандартные пути..."
    KEY_PATH="/var/lib/marzban-node/node-certs/key.pem"
fi

CERT_PATH="/var/lib/marzban-node/ssl/certificate.pem"

echo "   📍 Путь к сертификату: $CERT_PATH"
echo "   📍 Путь к ключу: $KEY_PATH"

echo ""
echo "2️⃣  Проверка наличия файлов на ноде..."
CERT_EXISTS=$(ssh root@185.126.67.67 "docker exec anomaly-node test -f $CERT_PATH && echo 'yes' || echo 'no'" 2>&1 | grep -v "password:")
KEY_EXISTS=$(ssh root@185.126.67.67 "docker exec anomaly-node test -f $KEY_PATH && echo 'yes' || echo 'no'" 2>&1 | grep -v "password:")

if [ "$CERT_EXISTS" = "yes" ] && [ "$KEY_EXISTS" = "yes" ]; then
    echo "   ✅ Оба файла найдены на ноде"
    
    echo ""
    echo "3️⃣  Копирование сертификата и ключа с ноды..."
    ssh root@185.126.67.67 "docker exec anomaly-node cat $CERT_PATH" > "$CERT_FILE" 2>&1 | grep -v "password:"
    ssh root@185.126.67.67 "docker exec anomaly-node cat $KEY_PATH" > "$KEY_FILE" 2>&1 | grep -v "password:"
    
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]; then
        echo "   ✅ Сертификат и ключ скопированы"
        echo "      Сертификат: $(wc -c < "$CERT_FILE") байт"
        echo "      Ключ: $(wc -c < "$KEY_FILE") байт"
    else
        echo "   ❌ Не удалось скопировать файлы или файлы пустые"
        exit 1
    fi
else
    echo "   ❌ Файлы не найдены на ноде"
    echo "      Сертификат: $CERT_EXISTS"
    echo "      Ключ: $KEY_EXISTS"
    exit 1
fi

echo ""
echo "4️⃣  Установка сертификата и ключа в базу данных Marzban..."
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "   📋 Обновление базы данных:"
    
    # Читаем содержимое файлов и передаем в Python скрипт через переменные окружения
    CERT_CONTENT=$(cat "$CERT_FILE" | sed "s/'/\\\'/g" | sed ':a;N;$!ba;s/\n/\\n/g')
    KEY_CONTENT=$(cat "$KEY_FILE" | sed "s/'/\\\'/g" | sed ':a;N;$!ba;s/\n/\\n/g')
    
    docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    cert = '''$CERT_CONTENT'''
    key = '''$KEY_CONTENT'''
    
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
        echo "5️⃣  Перезапуск Marzban для применения изменений..."
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


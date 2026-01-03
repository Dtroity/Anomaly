#!/bin/bash
# Синхронизация сертификата с ноды в базу данных Marzban

echo "🔄 Синхронизация сертификата с ноды в базу данных"
echo "=================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"
CERT_FILE="/tmp/node-cert-from-node.pem"

echo "1️⃣  Получение сертификата с ноды..."
echo "   📋 Подключение к ноде и получение сертификата:"
CERT_FETCH=$(docker exec anomaly-marzban python3 -c "
import ssl
import sys

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT
CERT_FILE = '$CERT_FILE'

try:
    # Получить сертификат сервера (это клиентский сертификат для Marzban)
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    server_cert = ssl.get_server_certificate((NODE_IP, NODE_PORT), ssl_version=ssl.PROTOCOL_TLS)
    
    # Сохранить в файл
    with open(CERT_FILE, 'w') as f:
        f.write(server_cert)
    
    print(f'SUCCESS: Certificate saved to {CERT_FILE}')
    print(f'Certificate length: {len(server_cert)}')
    print(f'First 3 lines:')
    for line in server_cert.split('\n')[:3]:
        print(f'  {line}')
        
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1)

if echo "$CERT_FETCH" | grep -q "SUCCESS"; then
    echo "   ✅ Сертификат получен с ноды"
    echo "$CERT_FETCH" | sed 's/^/      /'
else
    echo "   ❌ Не удалось получить сертификат с ноды"
    echo "$CERT_FETCH" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "2️⃣  Установка сертификата в базу данных Marzban..."
if [ -f "$CERT_FILE" ]; then
    echo "   📋 Использование скрипта fix-node-cert-in-db.sh:"
    chmod +x fix-node-cert-in-db.sh
    ./fix-node-cert-in-db.sh "$CERT_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "3️⃣  Перезапуск Marzban для применения изменений..."
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
        echo "   ❌ Ошибка при установке сертификата в базу данных"
        exit 1
    fi
else
    echo "   ❌ Файл сертификата не найден: $CERT_FILE"
    exit 1
fi


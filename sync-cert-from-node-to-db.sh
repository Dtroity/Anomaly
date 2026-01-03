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

echo "1️⃣  Получение клиентского сертификата с ноды..."
echo "   📋 Копирование сертификата с ноды через SSH:"
echo "   💡 Убедитесь, что у вас есть SSH доступ к ноде (185.126.67.67)"
echo ""

# Попробовать скопировать через SSH
if command -v scp &> /dev/null; then
    echo "   📋 Копирование через SCP..."
    scp root@185.126.67.67:/var/lib/marzban-node/ssl/certificate.pem "$CERT_FILE" 2>&1 | sed 's/^/      /'
    
    if [ -f "$CERT_FILE" ]; then
        CERT_FETCH="SUCCESS: Certificate copied from node"
        echo "   ✅ Сертификат скопирован с ноды"
    else
        CERT_FETCH="ERROR: Failed to copy certificate via SCP"
        echo "   ❌ Не удалось скопировать сертификат через SCP"
    fi
else
    echo "   ⚠️  SCP не найден, используйте альтернативный метод:"
    echo "      1. На ноде выполните:"
    echo "         docker exec anomaly-node cat /var/lib/marzban-node/ssl/certificate.pem > /tmp/node-cert.pem"
    echo "      2. Скопируйте файл вручную на Control Server в /tmp/node-cert-from-node.pem"
    echo "      3. Затем запустите: ./fix-node-cert-in-db.sh /tmp/node-cert-from-node.pem"
    exit 1
fi

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


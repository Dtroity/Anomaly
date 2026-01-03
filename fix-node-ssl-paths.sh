#!/bin/bash
# Исправление путей SSL сертификатов на ноде

echo "🔧 Исправление путей SSL сертификатов на ноде"
echo "=============================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ -f docker-compose.node.yml ]; then
    echo "✅ Обнаружена нода (VPS #2)"
    IS_NODE=true
elif [ -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на ноде (VPS #2), а не на Control Server"
    exit 1
else
    echo "⚠️  Не найдены файлы docker-compose"
    exit 1
fi

echo ""
echo "1️⃣  Проверка текущих сертификатов..."
if [ -f "/var/lib/marzban-node/ssl/certificate.pem" ]; then
    echo "   ✅ Клиентский сертификат найден: /var/lib/marzban-node/ssl/certificate.pem"
    CLIENT_CERT_SIZE=$(stat -c%s /var/lib/marzban-node/ssl/certificate.pem 2>/dev/null || echo "0")
    echo "      Размер: $CLIENT_CERT_SIZE байт"
else
    echo "   ❌ Клиентский сертификат не найден: /var/lib/marzban-node/ssl/certificate.pem"
fi

if [ -d "/var/lib/marzban-node/node-certs" ]; then
    echo "   📁 Директория node-certs существует"
    ls -la /var/lib/marzban-node/node-certs/ | sed 's/^/      /'
else
    echo "   ⚠️  Директория node-certs не существует: /var/lib/marzban-node/node-certs"
    echo "   💡 Создание директории..."
    mkdir -p /var/lib/marzban-node/node-certs
    chmod 755 /var/lib/marzban-node/node-certs
    echo "   ✅ Директория создана"
fi

echo ""
echo "2️⃣  Проверка серверных сертификатов..."
if [ -f "/var/lib/marzban-node/node-certs/certificate.pem" ] && [ -f "/var/lib/marzban-node/node-certs/key.pem" ]; then
    echo "   ✅ Серверные сертификаты найдены"
    SERVER_CERT_SIZE=$(stat -c%s /var/lib/marzban-node/node-certs/certificate.pem 2>/dev/null || echo "0")
    SERVER_KEY_SIZE=$(stat -c%s /var/lib/marzban-node/node-certs/key.pem 2>/dev/null || echo "0")
    echo "      Certificate: $SERVER_CERT_SIZE байт"
    echo "      Key: $SERVER_KEY_SIZE байт"
else
    echo "   ⚠️  Серверные сертификаты не найдены"
    echo "   💡 Генерация серверных сертификатов..."
    
    # Генерировать самоподписанный сертификат для сервера
    openssl req -x509 -newkey rsa:4096 -keyout /var/lib/marzban-node/node-certs/key.pem \
        -out /var/lib/marzban-node/node-certs/certificate.pem -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=marzban-node" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -f "/var/lib/marzban-node/node-certs/certificate.pem" ] && [ -f "/var/lib/marzban-node/node-certs/key.pem" ]; then
        chmod 644 /var/lib/marzban-node/node-certs/certificate.pem
        chmod 600 /var/lib/marzban-node/node-certs/key.pem
        echo "   ✅ Серверные сертификаты созданы"
    else
        echo "   ❌ Ошибка при создании серверных сертификатов"
        echo "   💡 Убедитесь, что openssl установлен: apt-get install openssl"
        exit 1
    fi
fi

echo ""
echo "3️⃣  Проверка .env.node..."
if [ ! -f ".env.node" ]; then
    echo "   ❌ Файл .env.node не найден"
    exit 1
fi

echo "   📋 Текущие настройки SSL:"
grep -E "SSL|UVICORN" .env.node | sed 's/^/      /'

echo ""
echo "4️⃣  Обновление .env.node..."
# Создать резервную копию
cp .env.node .env.node.backup.$(date +%Y%m%d_%H%M%S)
echo "   ✅ Резервная копия создана"

# Обновить пути
sed -i 's|^SSL_CLIENT_CERT_FILE=.*|SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem|' .env.node
sed -i 's|^UVICORN_SSL_CERTFILE=.*|UVICORN_SSL_CERTFILE=/var/lib/marzban-node/node-certs/certificate.pem|' .env.node
sed -i 's|^UVICORN_SSL_KEYFILE=.*|UVICORN_SSL_KEYFILE=/var/lib/marzban-node/node-certs/key.pem|' .env.node

# Убедиться, что переменные есть
if ! grep -q "^SSL_CLIENT_CERT_FILE=" .env.node; then
    echo "SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem" >> .env.node
fi
if ! grep -q "^UVICORN_SSL_CERTFILE=" .env.node; then
    echo "UVICORN_SSL_CERTFILE=/var/lib/marzban-node/node-certs/certificate.pem" >> .env.node
fi
if ! grep -q "^UVICORN_SSL_KEYFILE=" .env.node; then
    echo "UVICORN_SSL_KEYFILE=/var/lib/marzban-node/node-certs/key.pem" >> .env.node
fi
if ! grep -q "^UVICORN_SSL_CA_TYPE=" .env.node; then
    echo "UVICORN_SSL_CA_TYPE=private" >> .env.node
fi

echo "   ✅ .env.node обновлен"

echo ""
echo "5️⃣  Проверка обновленных настроек..."
echo "   📋 Новые настройки SSL:"
grep -E "SSL|UVICORN" .env.node | sed 's/^/      /'

echo ""
echo "6️⃣  Перезапуск ноды..."
if docker ps | grep -q anomaly-node; then
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart anomaly-node 2>/dev/null || \
    echo "   ⚠️  Не удалось перезапустить автоматически"
    echo "   💡 Попробуйте вручную: docker-compose -f docker-compose.node.yml restart marzban-node"
else
    echo "   ⚠️  Контейнер ноды не запущен"
    echo "   💡 Запустите: docker-compose -f docker-compose.node.yml up -d"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Проверьте логи ноды: docker-compose -f docker-compose.node.yml logs marzban-node --tail 30"
echo "   3. На Control Server в панели Marzban нажмите 'Переподключиться' для Node 1"
echo ""


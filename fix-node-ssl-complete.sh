#!/bin/bash
# Полное исправление SSL подключения ноды - выполняется на Node Server

echo "🔧 Полное исправление SSL подключения ноды Marzban"
echo "=================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.node.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Node Server (VPS #2)"
    echo ""
    echo "💡 Выполните на Node Server:"
    echo "   ssh root@185.126.67.67"
    echo "   cd /opt/Anomaly"
    echo "   ./fix-node-ssl-complete.sh"
    exit 1
fi

echo "✅ Обнаружен Node Server"
echo ""

# 1. Обновить код
echo "📥 Обновление кода..."
if [ -n "$(git status --porcelain)" ]; then
    echo "  💾 Сохранение локальных изменений..."
    git stash
fi
git pull

# 2. Проверить наличие клиентского сертификата
echo ""
echo "📋 Проверка клиентского сертификата..."
if [ -f "/var/lib/marzban-node/ssl/certificate.pem" ]; then
    echo "  ✅ Клиентский сертификат найден"
else
    echo "  ⚠️  Клиентский сертификат не найден"
    echo "  💡 Скачайте сертификат из панели Marzban и скопируйте:"
    echo "     scp /path/to/node-cert.pem root@185.126.67.67:/tmp/node-cert.pem"
    echo "     Затем: ./fix-node-ssl-connection.sh /tmp/node-cert.pem"
fi

# 3. Сгенерировать серверный сертификат
echo ""
echo "🔐 Генерация серверного SSL сертификата..."
mkdir -p node-certs

if [ ! -f node-certs/certificate.pem ] || [ ! -f node-certs/key.pem ]; then
    echo "  📋 Создание самоподписанного сертификата..."
    openssl req -x509 -newkey rsa:4096 -keyout node-certs/key.pem -out node-certs/certificate.pem -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Marzban/CN=185.126.67.67" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -f node-certs/certificate.pem ] && [ -f node-certs/key.pem ]; then
        chmod 644 node-certs/certificate.pem
        chmod 600 node-certs/key.pem
        echo "  ✅ Серверный сертификат создан"
    else
        echo "  ❌ Ошибка при создании сертификата"
        echo "  💡 Убедитесь, что openssl установлен: apt-get install openssl"
        exit 1
    fi
else
    echo "  ✅ Серверный сертификат уже существует"
fi

# 4. Проверить .env.node
echo ""
echo "📋 Проверка .env.node..."
if [ ! -f .env.node ]; then
    echo "  ⚠️  .env.node не найден, создаю..."
    touch .env.node
fi

# Обновить SSL настройки
if ! grep -q "^SSL_CLIENT_CERT_FILE=" .env.node; then
    echo "SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem" >> .env.node
fi
sed -i 's|^SSL_CLIENT_CERT_FILE=.*|SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem|' .env.node

if ! grep -q "^UVICORN_SSL_CERTFILE=" .env.node; then
    echo "UVICORN_SSL_CERTFILE=/var/lib/marzban-node/node-certs/certificate.pem" >> .env.node
fi
sed -i 's|^UVICORN_SSL_CERTFILE=.*|UVICORN_SSL_CERTFILE=/var/lib/marzban-node/node-certs/certificate.pem|' .env.node

if ! grep -q "^UVICORN_SSL_KEYFILE=" .env.node; then
    echo "UVICORN_SSL_KEYFILE=/var/lib/marzban-node/node-certs/key.pem" >> .env.node
fi
sed -i 's|^UVICORN_SSL_KEYFILE=.*|UVICORN_SSL_KEYFILE=/var/lib/marzban-node/node-certs/key.pem|' .env.node

if ! grep -q "^UVICORN_SSL_CA_TYPE=" .env.node; then
    echo "UVICORN_SSL_CA_TYPE=private" >> .env.node
fi
sed -i 's|^UVICORN_SSL_CA_TYPE=.*|UVICORN_SSL_CA_TYPE=private|' .env.node

if ! grep -q "^CONTROL_SERVER_URL=" .env.node; then
    echo "CONTROL_SERVER_URL=https://panel.anomaly-connect.online" >> .env.node
fi
sed -i 's|^CONTROL_SERVER_URL=.*|CONTROL_SERVER_URL=https://panel.anomaly-connect.online|' .env.node

echo "  ✅ .env.node обновлен"

# 5. Показать текущую конфигурацию
echo ""
echo "📋 Текущая конфигурация .env.node:"
grep -E "SSL_CLIENT_CERT_FILE|UVICORN_SSL|CONTROL_SERVER_URL" .env.node | sed 's/^/   /'

# 6. Проверить файлы сертификатов
echo ""
echo "📋 Проверка файлов сертификатов:"
if [ -f "/var/lib/marzban-node/ssl/certificate.pem" ]; then
    echo "   ✅ Клиентский: /var/lib/marzban-node/ssl/certificate.pem ($(stat -c%s /var/lib/marzban-node/ssl/certificate.pem) bytes)"
else
    echo "   ❌ Клиентский: /var/lib/marzban-node/ssl/certificate.pem (не найден)"
fi

if [ -f "node-certs/certificate.pem" ]; then
    echo "   ✅ Серверный cert: node-certs/certificate.pem ($(stat -c%s node-certs/certificate.pem) bytes)"
else
    echo "   ❌ Серверный cert: node-certs/certificate.pem (не найден)"
fi

if [ -f "node-certs/key.pem" ]; then
    echo "   ✅ Серверный key: node-certs/key.pem ($(stat -c%s node-certs/key.pem) bytes)"
else
    echo "   ❌ Серверный key: node-certs/key.pem (не найден)"
fi

# 7. Перезапустить ноду
echo ""
echo "🔄 Перезапуск ноды..."
if docker ps | grep -q anomaly-node; then
    if docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null; then
        echo "  ✅ Нода перезапущена"
    elif docker restart anomaly-node 2>/dev/null; then
        echo "  ✅ Нода перезапущена (через docker restart)"
    else
        echo "  ⚠️  Не удалось перезапустить автоматически"
        echo "  💡 Выполните вручную: docker-compose -f docker-compose.node.yml restart marzban-node"
    fi
else
    echo "  ⚠️  Нода не запущена"
    echo "  💡 Запустите: docker-compose -f docker-compose.node.yml up -d"
fi

# 8. Подождать и проверить логи
echo ""
echo "⏳ Ожидание запуска ноды (15 секунд)..."
sleep 15

echo ""
echo "📋 Статус ноды:"
if docker ps | grep -q anomaly-node; then
    echo "  ✅ Нода запущена"
else
    echo "  ❌ Нода не запущена"
fi

echo ""
echo "📋 Последние логи ноды (последние 30 строк):"
docker logs anomaly-node --tail=30 2>&1 | tail -30 | sed 's/^/   /'

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Проверьте логи выше на наличие ошибок SSL"
echo "   2. Если ошибок нет, вернитесь в панель Marzban: https://panel.anomaly-connect.online"
echo "   3. Перейдите в Nodes -> Node 1 -> нажмите 'Переподключиться'"
echo ""


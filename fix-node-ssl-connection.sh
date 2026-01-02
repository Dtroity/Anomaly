#!/bin/bash
# Полное исправление SSL подключения ноды Marzban
# Решает ошибку: "Connection aborted. Remote end closed connection without response"

echo "🔧 Исправление SSL подключения ноды Marzban"
echo "============================================"
echo ""
echo "Этот скрипт поможет исправить ошибку подключения ноды."
echo "Ошибка: 'Connection aborted. Remote end closed connection without response'"
echo ""
echo "📋 Инструкция:"
echo "=============="
echo ""
echo "1️⃣  На Control Server (VPS #1):"
echo "   - Откройте панель: https://panel.anomaly-connect.online"
echo "   - Перейдите в Nodes -> выберите ноду -> 'Скачать сертификат'"
echo "   - Сохраните файл (например, в /tmp/node-cert.pem)"
echo ""
echo "2️⃣  На Node Server (VPS #2, 185.126.67.67):"
echo "   - Подключитесь: ssh root@185.126.67.67"
echo "   - Выполните команды ниже"
echo ""

# Проверка, на каком сервере запущен скрипт
if [ -f docker-compose.node.yml ]; then
    echo "✅ Обнаружен Node Server (docker-compose.node.yml найден)"
    echo ""
    
    # Проверка наличия сертификата
    if [ $# -gt 0 ] && [ -f "$1" ]; then
        CERT_FILE="$1"
        echo "📋 Установка сертификата из: $CERT_FILE"
        
        # Создать директории
        mkdir -p /var/lib/marzban-node/ssl
        mkdir -p node-certs
        
        # Скопировать сертификат
        cp "$CERT_FILE" /var/lib/marzban-node/ssl/certificate.pem
        cp "$CERT_FILE" node-certs/certificate.pem
        chmod 644 /var/lib/marzban-node/ssl/certificate.pem
        chmod 644 node-certs/certificate.pem
        
        echo "✅ Сертификат установлен"
        echo ""
    else
        # Проверка существующего сертификата
        if [ -f "/var/lib/marzban-node/ssl/certificate.pem" ]; then
            echo "✅ Сертификат уже установлен: /var/lib/marzban-node/ssl/certificate.pem"
        else
            echo "❌ Сертификат не найден"
            echo ""
            echo "💡 Скачайте сертификат из панели Marzban и запустите:"
            echo "   ./fix-node-ssl-connection.sh /путь/к/сертификату.pem"
            exit 1
        fi
    fi
    
    # Обновить .env.node
    echo "📋 Обновление .env.node..."
    if [ ! -f .env.node ]; then
        echo "⚠️  .env.node не найден, создаю..."
        touch .env.node
    fi
    
    # Обновить SSL_CLIENT_CERT_FILE
    if ! grep -q "^SSL_CLIENT_CERT_FILE=" .env.node; then
        echo "SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem" >> .env.node
        echo "  ✅ Добавлен SSL_CLIENT_CERT_FILE"
    else
        sed -i 's|^SSL_CLIENT_CERT_FILE=.*|SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem|' .env.node
        echo "  ✅ Обновлен SSL_CLIENT_CERT_FILE"
    fi
    
    # Обновить UVICORN_SSL настройки для сервера
    if ! grep -q "^UVICORN_SSL_CERTFILE=" .env.node; then
        echo "UVICORN_SSL_CERTFILE=/var/lib/marzban-node/node-certs/certificate.pem" >> .env.node
        echo "  ✅ Добавлен UVICORN_SSL_CERTFILE"
    fi
    
    if ! grep -q "^UVICORN_SSL_KEYFILE=" .env.node; then
        echo "UVICORN_SSL_KEYFILE=/var/lib/marzban-node/node-certs/key.pem" >> .env.node
        echo "  ✅ Добавлен UVICORN_SSL_KEYFILE"
    fi
    
    if ! grep -q "^UVICORN_SSL_CA_TYPE=" .env.node; then
        echo "UVICORN_SSL_CA_TYPE=private" >> .env.node
        echo "  ✅ Добавлен UVICORN_SSL_CA_TYPE"
    fi
    
    # Проверить CONTROL_SERVER_URL
    if ! grep -q "^CONTROL_SERVER_URL=" .env.node; then
        echo "CONTROL_SERVER_URL=https://panel.anomaly-connect.online" >> .env.node
        echo "  ✅ Добавлен CONTROL_SERVER_URL"
    else
        CURRENT_URL=$(grep "^CONTROL_SERVER_URL=" .env.node | cut -d'=' -f2)
        if [ "$CURRENT_URL" != "https://panel.anomaly-connect.online" ]; then
            sed -i 's|^CONTROL_SERVER_URL=.*|CONTROL_SERVER_URL=https://panel.anomaly-connect.online|' .env.node
            echo "  ✅ Обновлен CONTROL_SERVER_URL"
        fi
    fi
    
    echo ""
    echo "📋 Текущая конфигурация .env.node:"
    grep -E "SSL_CLIENT_CERT_FILE|UVICORN_SSL|CONTROL_SERVER_URL" .env.node
    echo ""
    
    # Перезапустить ноду
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
    
    echo ""
    echo "⏳ Ожидание запуска ноды (10 секунд)..."
    sleep 10
    
    echo ""
    echo "📋 Проверка статуса ноды:"
    if docker ps | grep -q anomaly-node; then
        echo "  ✅ Нода запущена"
    else
        echo "  ❌ Нода не запущена"
    fi
    
    echo ""
    echo "📋 Последние логи ноды:"
    docker logs anomaly-node --tail=20 2>&1 | head -20
    
    echo ""
    echo "✅ Готово!"
    echo ""
    echo "💡 Следующие шаги:"
    echo "   1. Проверьте логи выше на наличие ошибок"
    echo "   2. Вернитесь в панель Marzban: https://panel.anomaly-connect.online"
    echo "   3. Перейдите в Nodes -> Node 1 -> нажмите 'Переподключиться'"
    echo ""
    
else
    echo "⚠️  Этот скрипт должен быть запущен на Node Server (VPS #2)"
    echo ""
    echo "💡 Инструкции для Node Server:"
    echo "   1. Подключитесь: ssh root@185.126.67.67"
    echo "   2. Перейдите: cd /opt/Anomaly"
    echo "   3. Обновите код: git pull"
    echo "   4. Скачайте сертификат с Control Server:"
    echo "      scp root@72.56.79.212:/var/lib/marzban-node/ssl/certificate.pem /tmp/node-cert.pem"
    echo "   5. Запустите скрипт: ./fix-node-ssl-connection.sh /tmp/node-cert.pem"
    echo ""
fi

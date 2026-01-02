#!/bin/bash
# Полное исправление подключения ноды Marzban
# Решает проблему "Connection aborted. Remote end closed connection without response"

echo "🔧 Полное исправление подключения ноды Marzban"
echo "=============================================="
echo ""
echo "Этот скрипт поможет исправить ошибку подключения ноды."
echo "Ошибка: 'Connection aborted. Remote end closed connection without response'"
echo ""
echo "💡 Инструкция:"
echo "   1. В панели Marzban нажмите 'Скачать сертификат' для ноды"
echo "   2. Сохраните файл на Control Server (например, в /tmp/node-cert.pem)"
echo "   3. Запустите этот скрипт с путем к сертификату:"
echo "      ./fix-node-connection-complete.sh /tmp/node-cert.pem"
echo ""
echo "Или если сертификат уже установлен, просто запустите:"
echo "      ./fix-node-connection-complete.sh"
echo ""

cd /opt/Anomaly || exit 1

# Если указан путь к сертификату, установить его
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
fi

# Проверить, что сертификат существует
if [ ! -f "/var/lib/marzban-node/ssl/certificate.pem" ]; then
    echo "❌ Сертификат не найден: /var/lib/marzban-node/ssl/certificate.pem"
    echo ""
    echo "💡 Скачайте сертификат из панели Marzban:"
    echo "   1. Откройте https://panel.anomaly-connect.online"
    echo "   2. Перейдите в Nodes -> выберите ноду -> 'Скачать сертификат'"
    echo "   3. Сохраните файл и запустите скрипт снова:"
    echo "      ./fix-node-connection-complete.sh /путь/к/сертификату.pem"
    exit 1
fi

echo "✅ Сертификат найден"
echo ""

# Проверить .env.node на ноде (если скрипт запущен на Control Server)
if [ -f .env.node ]; then
    echo "📋 Проверка .env.node на Control Server..."
    
    # Обновить SSL_CLIENT_CERT_FILE
    if ! grep -q "^SSL_CLIENT_CERT_FILE=" .env.node; then
        echo "SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem" >> .env.node
        echo "  ✅ Добавлен SSL_CLIENT_CERT_FILE"
    else
        sed -i 's|^SSL_CLIENT_CERT_FILE=.*|SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem|' .env.node
        echo "  ✅ Обновлен SSL_CLIENT_CERT_FILE"
    fi
    
    # Проверить UVICORN_SSL настройки для сервера
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
    
    echo ""
fi

# Инструкции для Node Server
echo "📋 Инструкции для Node Server (VPS #2):"
echo "========================================"
echo ""
echo "1. Подключитесь к Node Server (VPS #2):"
echo "   ssh root@185.126.67.67"
echo ""
echo "2. Перейдите в директорию проекта:"
echo "   cd /opt/Anomaly"
echo ""
echo "3. Скачайте сертификат с Control Server:"
echo "   scp root@72.56.79.212:/var/lib/marzban-node/ssl/certificate.pem /tmp/node-cert.pem"
echo ""
echo "4. Установите сертификат:"
echo "   mkdir -p /var/lib/marzban-node/ssl"
echo "   cp /tmp/node-cert.pem /var/lib/marzban-node/ssl/certificate.pem"
echo "   chmod 644 /var/lib/marzban-node/ssl/certificate.pem"
echo ""
echo "5. Обновите .env.node:"
echo "   echo 'SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem' >> .env.node"
echo ""
echo "6. Проверьте, что UVICORN_SSL настроены (для приема подключений):"
echo "   grep UVICORN_SSL .env.node"
echo "   # Должно быть:"
echo "   # UVICORN_SSL_CERTFILE=/var/lib/marzban-node/node-certs/certificate.pem"
echo "   # UVICORN_SSL_KEYFILE=/var/lib/marzban-node/node-certs/key.pem"
echo "   # UVICORN_SSL_CA_TYPE=private"
echo ""
echo "7. Перезапустите ноду:"
echo "   docker-compose -f docker-compose.node.yml restart marzban-node"
echo ""
echo "8. Проверьте логи:"
echo "   docker logs anomaly-node --tail=30"
echo ""
echo "9. Вернитесь в панель Marzban и нажмите 'Переподключиться'"
echo ""


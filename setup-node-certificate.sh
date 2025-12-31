#!/bin/bash

# Скрипт для установки сертификата на ноде

set -e

echo "🔐 Установка сертификата на ноде"
echo "================================="
echo ""

cd /opt/Anomaly

# 1. Проверить, есть ли сертификат
echo "📋 Инструкции по установке сертификата:"
echo ""
echo "1. На Control Server откройте панель Marzban:"
echo "   https://panel.anomaly-connect.online/dashboard/"
echo ""
echo "2. Перейдите в раздел 'Nodes' (Ноды)"
echo ""
echo "3. Найдите вашу ноду и нажмите 'Скачать сертификат'"
echo ""
echo "4. Скопируйте содержимое сертификата"
echo ""
echo "5. Создайте файл сертификата на ноде:"
echo ""

read -p "Введите путь к файлу сертификата (или нажмите Enter для пропуска): " CERT_PATH

if [ -n "$CERT_PATH" ] && [ -f "$CERT_PATH" ]; then
    echo "📁 Копирование сертификата..."
    
    # Создать директорию для сертификатов
    mkdir -p node-certs
    
    # Скопировать сертификат
    cp "$CERT_PATH" node-certs/certificate.pem
    
    # Создать симлинк для key (обычно используется тот же сертификат)
    if [ -f "${CERT_PATH%.pem}.key" ] || [ -f "${CERT_PATH%.pem}_key.pem" ]; then
        KEY_PATH="${CERT_PATH%.pem}.key"
        [ -f "$KEY_PATH" ] || KEY_PATH="${CERT_PATH%.pem}_key.pem"
        cp "$KEY_PATH" node-certs/key.pem
    else
        echo "⚠️  Файл ключа не найден, используем сертификат как ключ (временно)"
        cp "$CERT_PATH" node-certs/key.pem
    fi
    
    chmod 644 node-certs/certificate.pem
    chmod 600 node-certs/key.pem
    
    echo "✅ Сертификат скопирован"
    echo ""
    
    # Обновить .env.node
    echo "🔄 Обновление .env.node..."
    sed -i '/^UVICORN_SSL_CERTFILE=/d' .env.node
    sed -i '/^UVICORN_SSL_KEYFILE=/d' .env.node
    
    CERT_ABS_PATH="$(cd "$(dirname "$CERT_PATH")" && pwd)/$(basename "$CERT_PATH")"
    KEY_ABS_PATH="$(cd node-certs && pwd)/key.pem"
    
    echo "UVICORN_SSL_CERTFILE=/opt/Anomaly/node-certs/certificate.pem" >> .env.node
    echo "UVICORN_SSL_KEYFILE=/opt/Anomaly/node-certs/key.pem" >> .env.node
    
    echo "✅ .env.node обновлен"
    echo ""
    
    # Обновить docker-compose.node.yml для монтирования сертификатов
    echo "🔄 Обновление docker-compose.node.yml..."
    if ! grep -q "node-certs:/var/lib/marzban/ssl" docker-compose.node.yml; then
        # Добавить volume для сертификатов
        sed -i '/volumes:/a\      - ./node-certs:/var/lib/marzban/ssl:ro' docker-compose.node.yml
        echo "✅ Volume для сертификатов добавлен"
    fi
    
    # Обновить пути в .env.node для контейнера
    sed -i 's|UVICORN_SSL_CERTFILE=.*|UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/certificate.pem|' .env.node
    sed -i 's|UVICORN_SSL_KEYFILE=.*|UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem|' .env.node
    
    echo ""
    echo "🔄 Перезапуск ноды..."
    docker-compose -f docker-compose.node.yml down
    docker-compose -f docker-compose.node.yml up -d
    
    echo "⏳ Ожидание запуска (20 секунд)..."
    sleep 20
    
    echo ""
    echo "📋 Логи ноды:"
    docker-compose -f docker-compose.node.yml logs --tail=20 marzban-node | grep -E "Uvicorn running|ERROR" || docker-compose -f docker-compose.node.yml logs --tail=20 marzban-node
    
else
    echo ""
    echo "⚠️  Сертификат не указан или не найден"
    echo ""
    echo "📝 Ручная установка сертификата:"
    echo ""
    echo "1. Скачайте сертификат из панели Marzban"
    echo "2. Создайте директорию: mkdir -p /opt/Anomaly/node-certs"
    echo "3. Скопируйте сертификат:"
    echo "   - certificate.pem -> /opt/Anomaly/node-certs/certificate.pem"
    echo "   - key.pem -> /opt/Anomaly/node-certs/key.pem"
    echo "4. Обновите .env.node:"
    echo "   UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/certificate.pem"
    echo "   UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem"
    echo "5. Перезапустите ноду:"
    echo "   docker-compose -f docker-compose.node.yml restart marzban-node"
fi

echo ""
echo "✅ Готово!"


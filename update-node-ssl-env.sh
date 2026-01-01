#!/bin/bash

# Скрипт для обновления SSL переменных окружения в docker-compose.node.yml
# на основе значений из .env.node

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Обновление SSL переменных окружения в docker-compose.node.yml"
echo "================================================================="
echo ""

# Читать значения из .env.node
if [ -f ".env.node" ]; then
    SSL_CERT=$(grep "^UVICORN_SSL_CERTFILE=" .env.node | cut -d'=' -f2)
    SSL_KEY=$(grep "^UVICORN_SSL_KEYFILE=" .env.node | cut -d'=' -f2)
    SSL_CA_TYPE=$(grep "^UVICORN_SSL_CA_TYPE=" .env.node | cut -d'=' -f2)
    
    echo "📋 Значения из .env.node:"
    echo "  UVICORN_SSL_CERTFILE: $SSL_CERT"
    echo "  UVICORN_SSL_KEYFILE: $SSL_KEY"
    echo "  UVICORN_SSL_CA_TYPE: $SSL_CA_TYPE"
    echo ""
    
    # Если значения найдены, обновить docker-compose.node.yml
    if [ -n "$SSL_CERT" ] && [ -n "$SSL_KEY" ]; then
        echo "🔄 Обновление docker-compose.node.yml..."
        
        # Создать временный файл с обновленными переменными
        TEMP_FILE=$(mktemp)
        
        # Использовать sed для обновления переменных
        # Сначала проверить, есть ли уже эти переменные
        if grep -q "UVICORN_SSL_CERTFILE:" docker-compose.node.yml; then
            # Обновить существующие
            sed -i "s|UVICORN_SSL_CERTFILE:.*|UVICORN_SSL_CERTFILE: \"$SSL_CERT\"|" docker-compose.node.yml
            sed -i "s|UVICORN_SSL_KEYFILE:.*|UVICORN_SSL_KEYFILE: \"$SSL_KEY\"|" docker-compose.node.yml
            if [ -n "$SSL_CA_TYPE" ]; then
                if grep -q "UVICORN_SSL_CA_TYPE:" docker-compose.node.yml; then
                    sed -i "s|UVICORN_SSL_CA_TYPE:.*|UVICORN_SSL_CA_TYPE: \"$SSL_CA_TYPE\"|" docker-compose.node.yml
                else
                    sed -i "/UVICORN_SSL_KEYFILE:/a\      UVICORN_SSL_CA_TYPE: \"$SSL_CA_TYPE\"" docker-compose.node.yml
                fi
            fi
        else
            # Добавить новые переменные после SERVICE_PROTOCOL
            if [ -n "$SSL_CA_TYPE" ]; then
                sed -i "/SERVICE_PROTOCOL: \"rest\"/a\      # SSL сертификат и ключ для сервера (прием подключений от Marzban)\\n      UVICORN_SSL_CERTFILE: \"$SSL_CERT\"\\n      UVICORN_SSL_KEYFILE: \"$SSL_KEY\"\\n      UVICORN_SSL_CA_TYPE: \"$SSL_CA_TYPE\"" docker-compose.node.yml
            else
                sed -i "/SERVICE_PROTOCOL: \"rest\"/a\      # SSL сертификат и ключ для сервера (прием подключений от Marzban)\\n      UVICORN_SSL_CERTFILE: \"$SSL_CERT\"\\n      UVICORN_SSL_KEYFILE: \"$SSL_KEY\"" docker-compose.node.yml
            fi
        fi
        
        echo "  ✅ docker-compose.node.yml обновлен"
    else
        echo "  ⚠️  Не найдены UVICORN_SSL_CERTFILE или UVICORN_SSL_KEYFILE в .env.node"
    fi
else
    echo "  ❌ Файл .env.node не найден"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Пересоздайте контейнер: docker-compose -f docker-compose.node.yml up -d"
echo "   2. Проверьте переменные: docker exec anomaly-node env | grep UVICORN_SSL"
echo "   3. Проверьте логи: docker logs anomaly-node --tail=30"
echo ""


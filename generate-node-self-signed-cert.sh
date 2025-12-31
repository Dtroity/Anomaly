#!/bin/bash

# Скрипт для генерации самоподписанного SSL сертификата для ноды
# Это позволит ноде слушать на 0.0.0.0:62050 с SSL

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔐 Генерация самоподписанного SSL сертификата для ноды"
echo "========================================================"
echo ""

# 1. Проверить наличие openssl
if ! command -v openssl &> /dev/null; then
    echo "❌ openssl не установлен"
    echo "   Установите: apt-get update && apt-get install -y openssl"
    exit 1
fi
echo "✅ openssl установлен"
echo ""

# 2. Создать директорию для сертификатов
mkdir -p node-certs
echo "✅ Директория node-certs/ создана"
echo ""

# 3. Получить IP адрес ноды
NODE_IP=$(hostname -I | awk '{print $1}')
echo "📋 Параметры сертификата:"
echo "  IP адрес ноды: $NODE_IP"
echo "  Common Name: $NODE_IP"
echo ""

# 4. Генерировать приватный ключ
echo "🔑 Генерация приватного ключа..."
openssl genrsa -out node-certs/key.pem 2048
chmod 600 node-certs/key.pem
echo "✅ Приватный ключ создан: node-certs/key.pem"
echo ""

# 5. Генерировать запрос на сертификат (CSR)
echo "📝 Генерация запроса на сертификат..."
openssl req -new -key node-certs/key.pem -out node-certs/cert.csr \
    -subj "/C=US/ST=State/L=City/O=Anomaly VPN/CN=$NODE_IP" \
    -addext "subjectAltName=IP:$NODE_IP"
echo "✅ CSR создан"
echo ""

# 6. Генерировать самоподписанный сертификат
echo "📜 Генерация самоподписанного сертификата..."
openssl x509 -req -days 365 -in node-certs/cert.csr \
    -signkey node-certs/key.pem \
    -out node-certs/certificate.pem \
    -extensions v3_req \
    -extfile <(echo "[v3_req]"; echo "subjectAltName=IP:$NODE_IP")
chmod 644 node-certs/certificate.pem
echo "✅ Сертификат создан: node-certs/certificate.pem"
echo ""

# 7. Удалить временный CSR
rm -f node-certs/cert.csr
echo "✅ Временные файлы удалены"
echo ""

# 8. Проверить сертификаты
echo "📋 Проверка сертификатов:"
if [ -f node-certs/certificate.pem ] && [ -f node-certs/key.pem ]; then
    echo "  ✅ certificate.pem существует"
    echo "  ✅ key.pem существует"
    
    # Проверить формат
    if head -n 1 node-certs/certificate.pem | grep -q "BEGIN CERTIFICATE"; then
        echo "  ✅ certificate.pem имеет правильный формат"
    else
        echo "  ❌ certificate.pem имеет неправильный формат"
    fi
    
    if head -n 1 node-certs/key.pem | grep -q "BEGIN.*PRIVATE KEY"; then
        echo "  ✅ key.pem имеет правильный формат"
    else
        echo "  ❌ key.pem имеет неправильный формат"
    fi
    
    # Показать информацию о сертификате
    echo ""
    echo "📋 Информация о сертификате:"
    openssl x509 -in node-certs/certificate.pem -noout -subject -dates 2>/dev/null || true
    echo ""
else
    echo "  ❌ Сертификаты не найдены"
    exit 1
fi

# 9. Обновить .env.node
echo "🔄 Обновление .env.node..."
if ! grep -q "^UVICORN_SSL_CERTFILE=" .env.node; then
    echo "UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/certificate.pem" >> .env.node
fi
if ! grep -q "^UVICORN_SSL_KEYFILE=" .env.node; then
    echo "UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem" >> .env.node
fi
if ! grep -q "^UVICORN_HOST=" .env.node; then
    echo "UVICORN_HOST=0.0.0.0" >> .env.node
fi

# Убедиться, что UVICORN_HOST=0.0.0.0
sed -i 's/^UVICORN_HOST=.*/UVICORN_HOST=0.0.0.0/' .env.node
echo "✅ .env.node обновлен"
echo ""

# 10. Информация о следующем шаге
echo "✅ Готово!"
echo ""
echo "📝 Следующие шаги:"
echo "   1. Запустите: ./fix-node-ssl-mount.sh"
echo "   2. Проверьте логи: docker-compose -f docker-compose.node.yml logs marzban-node"
echo "   3. Убедитесь, что нода слушает на https://0.0.0.0:62050"
echo ""
echo "💡 Примечание:"
echo "   Это самоподписанный сертификат, поэтому Control Server может выдать предупреждение"
echo "   о недоверенном сертификате. Это нормально для внутреннего использования."
echo ""


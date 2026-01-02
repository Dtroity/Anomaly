#!/bin/bash
# Генерация самоподписанного SSL сертификата для ноды Marzban

echo "🔐 Генерация SSL сертификата для ноды Marzban"
echo "=============================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.node.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Node Server (VPS #2)"
    echo ""
    echo "💡 Выполните на Node Server:"
    echo "   ssh root@185.126.67.67"
    echo "   cd /opt/Anomaly"
    echo "   ./generate-node-server-cert.sh"
    exit 1
fi

echo "✅ Обнаружен Node Server"
echo ""

# Создать директорию для сертификатов
mkdir -p node-certs

# Генерация самоподписанного сертификата
echo "📋 Генерация самоподписанного сертификата..."
openssl req -x509 -newkey rsa:4096 -keyout node-certs/key.pem -out node-certs/certificate.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=185.126.67.67" 2>/dev/null

if [ $? -eq 0 ] && [ -f node-certs/certificate.pem ] && [ -f node-certs/key.pem ]; then
    chmod 644 node-certs/certificate.pem
    chmod 600 node-certs/key.pem
    echo "  ✅ Сертификат создан: node-certs/certificate.pem"
    echo "  ✅ Ключ создан: node-certs/key.pem"
else
    echo "  ❌ Ошибка при создании сертификата"
    echo "  💡 Убедитесь, что openssl установлен: apt-get install openssl"
    exit 1
fi

echo ""
echo "📋 Информация о сертификате:"
openssl x509 -in node-certs/certificate.pem -text -noout | grep -E "Subject:|Issuer:|Not Before|Not After" | head -4

echo ""
echo "🔄 Перезапуск ноды..."
if docker ps | grep -q anomaly-node; then
    docker-compose -f docker-compose.node.yml restart marzban-node 2>/dev/null || \
    docker restart anomaly-node 2>/dev/null
    echo "  ✅ Нода перезапущена"
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


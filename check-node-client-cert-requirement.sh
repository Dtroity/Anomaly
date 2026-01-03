#!/bin/bash
# Проверка, требует ли нода клиентский сертификат для /connect

echo "🔍 Проверка требования клиентского сертификата на ноде"
echo "======================================================"
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.node.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Node Server (VPS #2)"
    exit 1
fi

echo "✅ Обнаружена нода"
echo ""

echo "1️⃣  Проверка конфигурации ноды..."
echo "   📋 Переменные окружения SSL:"
docker exec anomaly-node env 2>/dev/null | grep -E "SSL|UVICORN" | sed 's/^/      /' || echo "      ⚠️  Не удалось получить переменные окружения"

echo ""
echo "2️⃣  Проверка сертификатов на ноде..."
echo "   📋 Клиентский сертификат (для подключения к Control Server):"
if docker exec anomaly-node test -f /var/lib/marzban-node/ssl/certificate.pem 2>/dev/null; then
    CERT_SIZE=$(docker exec anomaly-node stat -c%s /var/lib/marzban-node/ssl/certificate.pem 2>/dev/null || echo "0")
    echo "      ✅ Найден: /var/lib/marzban-node/ssl/certificate.pem ($CERT_SIZE bytes)"
else
    echo "      ❌ Не найден: /var/lib/marzban-node/ssl/certificate.pem"
fi

echo ""
echo "   📋 Серверные сертификаты (для приема подключений):"
if docker exec anomaly-node test -f /var/lib/marzban-node/node-certs/certificate.pem 2>/dev/null; then
    SERVER_CERT_SIZE=$(docker exec anomaly-node stat -c%s /var/lib/marzban-node/node-certs/certificate.pem 2>/dev/null || echo "0")
    echo "      ✅ Certificate: /var/lib/marzban-node/node-certs/certificate.pem ($SERVER_CERT_SIZE bytes)"
else
    echo "      ❌ Не найден: /var/lib/marzban-node/node-certs/certificate.pem"
fi

if docker exec anomaly-node test -f /var/lib/marzban-node/node-certs/key.pem 2>/dev/null; then
    SERVER_KEY_SIZE=$(docker exec anomaly-node stat -c%s /var/lib/marzban-node/node-certs/key.pem 2>/dev/null || echo "0")
    echo "      ✅ Key: /var/lib/marzban-node/node-certs/key.pem ($SERVER_KEY_SIZE bytes)"
else
    echo "      ❌ Не найден: /var/lib/marzban-node/node-certs/key.pem"
fi

echo ""
echo "3️⃣  Проверка логов ноды на ошибки SSL..."
echo "   📋 Последние 200 строк логов (фильтр по SSL/TLS):"
docker logs anomaly-node --tail 200 2>&1 | grep -i -E "(ssl|tls|cert|client.*cert|mutual)" | tail -20 | sed 's/^/      /' || echo "      ℹ️  Нет записей о SSL/TLS"

echo ""
echo "4️⃣  Рекомендации:"
echo "   💡 Если нода не принимает клиентский сертификат:"
echo "      1. Проверьте, что сертификат в базе данных Marzban соответствует сертификату на ноде"
echo "      2. Убедитесь, что сертификат был скачан из панели Marzban для этой конкретной ноды"
echo "      3. Попробуйте переустановить сертификат:"
echo "         - Скачайте сертификат из панели: Nodes -> Node 1 -> Скачать сертификат"
echo "         - На Control Server: ./fix-node-cert-in-db.sh /tmp/node-cert.pem"
echo "      4. Проверьте, что нода использует правильный сертификат:"
echo "         docker exec anomaly-node cat /var/lib/marzban-node/ssl/certificate.pem | head -5"
echo ""


#!/bin/bash
# Синхронизация сертификата ноды между базой данных и нодой

echo "🔄 Синхронизация сертификата ноды"
echo "=================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Получение сертификата из базы данных Marzban..."
DB_CERT=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

with GetDB() as db:
    tls = db.query(TLS).first()
    if tls:
        print(tls.certificate)
    else:
        print('ERROR: TLS certificate not found')
        sys.exit(1)
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources")

if echo "$DB_CERT" | grep -q "ERROR"; then
    echo "   ❌ $DB_CERT"
    exit 1
fi

DB_CERT_HASH=$(echo "$DB_CERT" | head -3 | md5sum | cut -d' ' -f1)
echo "   ✅ Сертификат получен из базы данных"
echo "      Hash (первые 3 строки): $DB_CERT_HASH"

echo ""
echo "2️⃣  Инструкция по синхронизации:"
echo ""
echo "   📋 Сертификат в базе данных НЕ совпадает с сертификатом на ноде"
echo ""
echo "   💡 Решение 1: Обновить сертификат в базе данных (рекомендуется)"
echo "      1. Откройте панель: https://panel.anomaly-connect.online"
echo "      2. Перейдите в Nodes -> Node 1"
echo "      3. Нажмите 'Скачать сертификат'"
echo "      4. Скопируйте содержимое сертификата"
echo "      5. Сохраните в файл: nano /tmp/node-cert.pem"
echo "      6. Запустите: ./fix-node-cert-in-db.sh /tmp/node-cert.pem"
echo ""
echo "   💡 Решение 2: Обновить сертификат на ноде"
echo "      1. На Control Server получите сертификат из базы данных:"
echo "         docker exec anomaly-marzban python3 -c \""
echo "         import sys; sys.path.insert(0, '/code');"
echo "         from app.db import GetDB; from app.db.models import TLS;"
echo "         with GetDB() as db:"
echo "             tls = db.query(TLS).first();"
echo "             print(tls.certificate)\" | grep -v 'UserWarning' > /tmp/node-cert-from-db.pem"
echo "      2. Скопируйте на ноду:"
echo "         scp /tmp/node-cert-from-db.pem root@185.126.67.67:/tmp/"
echo "      3. На ноде установите:"
echo "         ./install-node-cert.sh /tmp/node-cert-from-db.pem"
echo ""

echo "3️⃣  Показываю первые строки сертификата из базы данных для сравнения:"
echo "$DB_CERT" | head -5 | sed 's/^/      /'

echo ""
echo "✅ Проверка завершена!"
echo ""


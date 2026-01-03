#!/bin/bash
# Проверка синхронизации сертификата между нодой и базой данных

echo "🔍 Проверка синхронизации сертификата"
echo "======================================"
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

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            print(tls.certificate)
        else:
            print('ERROR: TLS record not found')
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$DB_CERT" | grep -q "BEGIN CERTIFICATE"; then
    DB_CERT_HASH=$(echo "$DB_CERT" | grep -A 1 "BEGIN CERTIFICATE" | tail -1 | cut -c1-50)
    echo "   ✅ Сертификат найден в базе данных"
    echo "      Hash (первые 50 символов): $DB_CERT_HASH"
else
    echo "   ❌ Сертификат не найден в базе данных"
    echo "$DB_CERT" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "2️⃣  Получение сертификата с ноды..."
NODE_CERT=$(ssh root@185.126.67.67 "docker exec anomaly-node cat /var/lib/marzban-node/ssl/certificate.pem" 2>&1 | grep -v "password:")

if echo "$NODE_CERT" | grep -q "BEGIN CERTIFICATE"; then
    NODE_CERT_HASH=$(echo "$NODE_CERT" | grep -A 1 "BEGIN CERTIFICATE" | tail -1 | cut -c1-50)
    echo "   ✅ Сертификат найден на ноде"
    echo "      Hash (первые 50 символов): $NODE_CERT_HASH"
else
    echo "   ❌ Сертификат не найден на ноде"
    echo "$NODE_CERT" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "3️⃣  Сравнение сертификатов..."
if [ "$DB_CERT_HASH" = "$NODE_CERT_HASH" ]; then
    echo "   ✅ Сертификаты СОВПАДАЮТ"
else
    echo "   ❌ Сертификаты НЕ СОВПАДАЮТ"
    echo "      База данных: $DB_CERT_HASH"
    echo "      Нода:        $NODE_CERT_HASH"
    echo ""
    echo "   💡 Решение: Синхронизируйте сертификат с ноды в базу данных:"
    echo "      ./sync-cert-and-key-from-node.sh"
fi

echo ""
echo "4️⃣  Проверка детальных ошибок подключения..."
echo "   📋 Последние ошибки в логах Marzban:"
docker logs anomaly-marzban --tail 100 2>&1 | grep -i -E "(error|exception|traceback|ssl|certificate|key|mismatch)" | tail -10 | sed 's/^/      /' || echo "      ℹ️  Нет явных ошибок в последних логах"

echo ""
echo "✅ Проверка завершена!"
echo ""


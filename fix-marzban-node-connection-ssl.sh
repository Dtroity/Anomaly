#!/bin/bash
# Исправление SSL подключения Marzban к ноде

echo "🔧 Исправление SSL подключения Marzban к ноде"
echo "=============================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка сертификата в базе данных..."
CERT_CHECK=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if not tls:
            print('ERROR: TLS certificate not found in database')
            sys.exit(1)
        
        cert_len = len(tls.certificate)
        key_len = len(tls.key)
        
        print(f'SUCCESS: Certificate found')
        print(f'Certificate length: {cert_len}')
        print(f'Key length: {key_len}')
        
        # Проверить первые строки сертификата
        cert_lines = tls.certificate.split('\n')[:3]
        print(f'First 3 lines: {cert_lines}')
        
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$CERT_CHECK" | grep -q "SUCCESS"; then
    echo "   ✅ Сертификат найден в базе данных"
    echo "$CERT_CHECK" | sed 's/^/      /'
else
    echo "   ❌ Сертификат не найден в базе данных"
    echo "$CERT_CHECK" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "2️⃣  Перезапуск Marzban для применения изменений..."
echo "   🔄 Остановка Marzban..."
docker-compose stop marzban

echo "   ⏳ Ожидание 3 секунды..."
sleep 3

echo "   🔄 Запуск Marzban..."
docker-compose up -d marzban

echo "   ⏳ Ожидание запуска Marzban (10 секунд)..."
sleep 10

echo "   ✅ Проверка статуса Marzban..."
MARZBAN_STATUS=$(docker-compose ps marzban | grep -E "Up|running" || echo "NOT_RUNNING")
if echo "$MARZBAN_STATUS" | grep -q "Up\|running"; then
    echo "      ✅ Marzban запущен"
else
    echo "      ⚠️  Marzban может быть не запущен, проверьте: docker-compose ps marzban"
fi

echo ""
echo "3️⃣  Проверка подключения к ноде..."
echo "   ⏳ Ожидание 5 секунд для стабилизации..."
sleep 5

echo "   📋 Проверка последних попыток подключения в логах:"
docker logs anomaly-marzban --tail 20 2>&1 | grep -E "(Connecting|Unable to connect|node)" | tail -5 | sed 's/^/      /' || echo "      ℹ️  Нет записей в последних логах"

echo ""
echo "✅ Готово!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Подождите 10-20 секунд"
echo "   2. Откройте панель: https://panel.anomaly-connect.online"
echo "   3. Перейдите в Nodes -> Node 1"
echo "   4. Нажмите 'Переподключиться'"
echo "   5. Проверьте статус ноды"
echo ""
echo "   Если проблема сохраняется, проверьте логи:"
echo "   docker logs -f anomaly-marzban | grep -E '(node|connect|error)'"
echo ""


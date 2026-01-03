#!/bin/bash
# Проверка синхронизации ключа и детальная диагностика подключения

echo "🔍 Проверка синхронизации ключа и диагностика подключения"
echo "=========================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Получение ключа из базы данных Marzban..."
DB_KEY=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            print(tls.key)
        else:
            print('ERROR: TLS record not found')
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$DB_KEY" | grep -q "BEGIN.*PRIVATE KEY"; then
    DB_KEY_HASH=$(echo "$DB_KEY" | grep -A 1 "BEGIN.*PRIVATE KEY" | tail -1 | cut -c1-50)
    echo "   ✅ Ключ найден в базе данных"
    echo "      Hash (первые 50 символов): $DB_KEY_HASH"
else
    echo "   ❌ Ключ не найден в базе данных"
    echo "$DB_KEY" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "2️⃣  Получение ключа с ноды..."
NODE_KEY_PATH=$(ssh root@185.126.67.67 "docker exec anomaly-node env | grep UVICORN_SSL_KEYFILE" 2>&1 | grep -v "password:" | cut -d'=' -f2)
NODE_KEY=$(ssh root@185.126.67.67 "docker exec anomaly-node cat $NODE_KEY_PATH" 2>&1 | grep -v "password:")

if echo "$NODE_KEY" | grep -q "BEGIN.*PRIVATE KEY"; then
    NODE_KEY_HASH=$(echo "$NODE_KEY" | grep -A 1 "BEGIN.*PRIVATE KEY" | tail -1 | cut -c1-50)
    echo "   ✅ Ключ найден на ноде"
    echo "      Путь: $NODE_KEY_PATH"
    echo "      Hash (первые 50 символов): $NODE_KEY_HASH"
else
    echo "   ❌ Ключ не найден на ноде"
    echo "$NODE_KEY" | sed 's/^/      /'
    exit 1
fi

echo ""
echo "3️⃣  Сравнение ключей..."
if [ "$DB_KEY_HASH" = "$NODE_KEY_HASH" ]; then
    echo "   ✅ Ключи СОВПАДАЮТ"
else
    echo "   ❌ Ключи НЕ СОВПАДАЮТ"
    echo "      База данных: $DB_KEY_HASH"
    echo "      Нода:        $NODE_KEY_HASH"
    echo ""
    echo "   💡 Решение: Синхронизируйте ключ с ноды в базу данных:"
    echo "      ./sync-cert-and-key-from-node.sh"
fi

echo ""
echo "4️⃣  Тест подключения с использованием сертификата и ключа из базы данных..."
CONNECTION_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import requests
import tempfile
import ssl

NODE_IP = '185.126.67.67'
NODE_PORT = 62050

try:
    from app.db import GetDB
    from app.db.models import TLS
    from app.xray.node import SANIgnoringAdaptor
    
    # Получить сертификат и ключ из базы данных
    with GetDB() as db:
        tls = db.query(TLS).first()
        if not tls:
            print('ERROR: TLS record not found')
            sys.exit(1)
        
        cert_content = tls.certificate
        key_content = tls.key
        
        # Создать временные файлы
        cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        
        cert_file.write(cert_content)
        cert_file.flush()
        
        key_file.write(key_content)
        key_file.flush()
    
    # Получить сертификат сервера
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    try:
        server_cert = ssl.get_server_certificate((NODE_IP, NODE_PORT), ssl_version=ssl.PROTOCOL_TLS)
        server_cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        server_cert_file.write(server_cert)
        server_cert_file.flush()
    except Exception as e:
        print(f'ERROR getting server cert: {str(e)[:200]}')
        sys.exit(1)
    
    # Создать сессию как Marzban
    session = requests.Session()
    session.mount('https://', SANIgnoringAdaptor())
    session.cert = (cert_file.name, key_file.name)
    session.verify = server_cert_file.name
    
    # Попробовать подключиться
    connect_url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    print(f'INFO: Connecting to {connect_url}...')
    
    try:
        response = session.post(connect_url, json={'session_id': None}, timeout=10)
        if response.status_code == 200:
            data = response.json()
            session_id = data.get('session_id', 'N/A')
            print(f'SUCCESS: Connected, Session ID: {session_id[:30]}...')
        else:
            print(f'ERROR: HTTP {response.status_code}')
            print(f'Response: {response.text[:200]}')
    except requests.exceptions.SSLError as e:
        print(f'SSL_ERROR: {str(e)[:300]}')
    except requests.exceptions.ConnectionError as e:
        print(f'CONNECTION_ERROR: {str(e)[:300]}')
    except Exception as e:
        print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
        import traceback
        traceback.print_exc()
        
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
" 2>&1 | grep -v "UserWarning" | grep -v "InsecureRequestWarning")

echo "$CONNECTION_TEST" | sed 's/^/      /'

echo ""
echo "5️⃣  Проверка логов ноды при попытке подключения..."
echo "   📋 Последние запросы на ноде:"
ssh root@185.126.67.67 "docker logs anomaly-node --tail 20 2>&1 | grep -E '(POST|connect|error|SSL)'" 2>&1 | grep -v "password:" | sed 's/^/      /' || echo "      ℹ️  Нет запросов в последних логах"

echo ""
echo "✅ Проверка завершена!"
echo ""


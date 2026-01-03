#!/bin/bash
# Тест получения сертификата сервера ноды (как делает Marzban)

echo "🔍 Тест получения сертификата сервера ноды"
echo "=========================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "1️⃣  Тест получения сертификата сервера (как делает Marzban)..."
echo "   📋 Попытка получить сертификат через ssl.get_server_certificate():"
CERT_TEST=$(docker exec anomaly-marzban python3 -c "
import ssl
import sys

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT

try:
    # Попробовать получить сертификат сервера (как делает Marzban в connect())
    print(f'INFO: Attempting to get server certificate from {NODE_IP}:{NODE_PORT}...')
    
    # Создать SSL context без проверки (для получения сертификата)
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    try:
        server_cert = ssl.get_server_certificate((NODE_IP, NODE_PORT), ssl_version=ssl.PROTOCOL_TLS)
        print('SUCCESS: Server certificate obtained')
        print(f'Certificate length: {len(server_cert)}')
        print(f'First 3 lines:')
        for line in server_cert.split('\n')[:3]:
            print(f'  {line}')
    except ssl.SSLError as e:
        print(f'SSL_ERROR: {str(e)[:300]}')
        print('REASON: Cannot get server certificate due to SSL error')
        sys.exit(1)
    except Exception as e:
        print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
        import traceback
        traceback.print_exc()
        sys.exit(1)
        
except Exception as e:
    print(f'SETUP_ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1)

if echo "$CERT_TEST" | grep -q "SUCCESS"; then
    echo "   ✅ Сертификат сервера получен успешно"
    echo "$CERT_TEST" | sed 's/^/      /'
else
    echo "   ❌ Не удалось получить сертификат сервера"
    echo "$CERT_TEST" | sed 's/^/      /'
    echo ""
    echo "   💡 Это объясняет, почему Marzban не может подключиться!"
    echo "      Marzban пытается получить сертификат сервера перед подключением,"
    echo "      и если это не удается, подключение не происходит."
fi

echo ""
echo "2️⃣  Тест подключения с использованием полученного сертификата..."
if echo "$CERT_TEST" | grep -q "SUCCESS"; then
    CONNECTION_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import ssl
import requests
import tempfile

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT

try:
    from app.db import GetDB
    from app.db.models import TLS
    
    # Получить клиентский сертификат
    with GetDB() as db:
        tls = db.query(TLS).first()
        if not tls:
            print('ERROR: TLS certificate not found')
            sys.exit(1)
        
        client_cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        client_key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        
        client_cert_file.write(tls.certificate)
        client_cert_file.flush()
        
        client_key_file.write(tls.key)
        client_key_file.flush()
    
    # Получить сертификат сервера
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    server_cert = ssl.get_server_certificate((NODE_IP, NODE_PORT), ssl_version=ssl.PROTOCOL_TLS)
    server_cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
    server_cert_file.write(server_cert)
    server_cert_file.flush()
    
    # Создать сессию как Marzban
    from app.xray.node import SANIgnoringAdaptor
    session = requests.Session()
    session.mount('https://', SANIgnoringAdaptor())
    session.cert = (client_cert_file.name, client_key_file.name)
    session.verify = server_cert_file.name  # Как делает Marzban
    
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
    except Exception as e:
        print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
        
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
" 2>&1 | grep -v "UserWarning" | grep -v "InsecureRequestWarning")
    
    echo "$CONNECTION_TEST" | sed 's/^/      /'
fi

echo ""
echo "✅ Тест завершен!"
echo ""

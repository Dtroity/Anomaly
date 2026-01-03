#!/bin/bash
# Тест получения сертификата сервера ноды (как делает Marzban)

echo "🔍 Тест получения сертификата сервера ноды"
echo "==========================================="
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

echo "1️⃣  Тест получения сертификата сервера (как Marzban)..."
CERT_TEST=$(docker exec anomaly-marzban python3 -c "
import ssl
import socket

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT

try:
    # Получить сертификат сервера (как делает Marzban в connect())
    cert = ssl.get_server_certificate((NODE_IP, NODE_PORT))
    print('SUCCESS: Server certificate obtained')
    print(f'Certificate length: {len(cert)}')
    print(f'Certificate preview: {cert[:100]}...')
    if cert.startswith('-----BEGIN'):
        print('Certificate format: Valid PEM')
    else:
        print('Certificate format: Invalid')
except ssl.SSLError as e:
    print(f'SSL_ERROR: {type(e).__name__}: {str(e)[:300]}')
except socket.timeout as e:
    print(f'TIMEOUT_ERROR: {type(e).__name__}: {str(e)[:300]}')
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
" 2>&1)

if echo "$CERT_TEST" | grep -q "SUCCESS"; then
    echo "   ✅ Сертификат сервера получен успешно"
    echo "$CERT_TEST" | sed 's/^/      /'
else
    echo "   ❌ Не удалось получить сертификат сервера:"
    echo "$CERT_TEST" | sed 's/^/      /'
fi

echo ""
echo "2️⃣  Тест подключения с клиентским сертификатом и получением сертификата сервера..."
FULL_CONNECT_TEST=$(docker exec anomaly-marzban python3 -c "
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
    
    # Получить клиентский сертификат из базы данных
    with GetDB() as db:
        tls = db.query(TLS).first()
        if not tls:
            print('ERROR: TLS certificate not found in database')
            sys.exit(1)
        
        # Создать временные файлы для сертификата и ключа
        cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        
        cert_file.write(tls.certificate)
        cert_file.flush()
        
        key_file.write(tls.key)
        key_file.flush()
        
        print(f'Client cert file: {cert_file.name}')
        print(f'Client key file: {key_file.name}')
    
    # Получить сертификат сервера
    try:
        server_cert = ssl.get_server_certificate((NODE_IP, NODE_PORT))
        print(f'SUCCESS: Server certificate obtained ({len(server_cert)} bytes)')
    except Exception as e:
        print(f'ERROR getting server cert: {type(e).__name__}: {str(e)[:200]}')
        sys.exit(1)
    
    # Создать сессию с клиентским сертификатом
    session = requests.Session()
    session.verify = False  # Отключить проверку сертификата сервера
    session.cert = (cert_file.name, key_file.name)
    
    # Попробовать подключиться к /connect
    url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    data = {'session_id': None}
    
    try:
        response = session.post(url, json=data, timeout=10, verify=False)
        print(f'SUCCESS: POST /connect - HTTP {response.status_code}')
        result = response.json()
        if 'session_id' in result:
            print(f'Session ID: {result[\"session_id\"][:50]}...')
        else:
            print(f'Response: {str(result)[:200]}')
    except requests.exceptions.RequestException as e:
        print(f'REQUEST_ERROR: {type(e).__name__}: {str(e)[:300]}')
        sys.exit(1)
        
except Exception as e:
    print(f'SETUP_ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$FULL_CONNECT_TEST" | grep -q "SUCCESS.*POST /connect"; then
    echo "   ✅ Полное подключение успешно!"
    echo "$FULL_CONNECT_TEST" | sed 's/^/      /'
else
    echo "   ❌ Полное подключение не удалось:"
    echo "$FULL_CONNECT_TEST" | sed 's/^/      /'
fi

echo ""
echo "✅ Тест завершен!"
echo ""


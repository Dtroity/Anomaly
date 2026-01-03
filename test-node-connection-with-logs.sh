#!/bin/bash
# Тест подключения к ноде с одновременным просмотром логов ноды

echo "🔍 Тест подключения к ноде с просмотром логов"
echo "=============================================="
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

echo "1️⃣  Тест простого подключения (как /ping и / работают)..."
echo "   📋 Попытка подключения БЕЗ клиентского сертификата:"
SIMPLE_TEST=$(docker exec anomaly-marzban python3 -c "
import requests
import urllib3
urllib3.disable_warnings()

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT

try:
    # Простое подключение без клиентского сертификата
    url = f'https://{NODE_IP}:{NODE_PORT}/ping'
    print(f'INFO: Connecting to {url}...')
    
    response = requests.post(url, json={}, timeout=5, verify=False)
    if response.status_code == 200:
        print(f'SUCCESS: HTTP {response.status_code}')
        print(f'Response: {response.text[:200]}')
    else:
        print(f'ERROR: HTTP {response.status_code}')
        print(f'Response: {response.text[:200]}')
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
" 2>&1 | grep -v "InsecureRequestWarning")

echo "$SIMPLE_TEST" | sed 's/^/      /'

echo ""
echo "2️⃣  Тест подключения с клиентским сертификатом..."
echo "   📋 Попытка подключения С клиентским сертификатом:"
CLIENT_CERT_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import requests
import tempfile
import urllib3
urllib3.disable_warnings()

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
    
    # Попробовать подключиться с клиентским сертификатом
    url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    print(f'INFO: Connecting to {url} with client cert...')
    
    session = requests.Session()
    session.verify = False
    session.cert = (client_cert_file.name, client_key_file.name)
    
    try:
        response = session.post(url, json={'session_id': None}, timeout=10)
        if response.status_code == 200:
            data = response.json()
            session_id = data.get('session_id', 'N/A')
            print(f'SUCCESS: Connected, Session ID: {session_id[:30]}...')
        else:
            print(f'ERROR: HTTP {response.status_code}')
            print(f'Response: {response.text[:200]}')
    except requests.exceptions.ConnectionError as e:
        print(f'CONNECTION_ERROR: {str(e)[:300]}')
        print('REASON: Connection aborted - возможно, нода закрывает соединение')
        print('        Это может означать, что клиентский сертификат неверен')
    except Exception as e:
        print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
        
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
" 2>&1 | grep -v "UserWarning" | grep -v "InsecureRequestWarning")

echo "$CLIENT_CERT_TEST" | sed 's/^/      /'

echo ""
echo "3️⃣  Рекомендации:"
echo "   💡 Если /ping работает, но /connect не работает:"
echo "      - Проблема в клиентском сертификате"
echo "      - Нода требует клиентский сертификат для /connect, но не для /ping"
echo "      - Проверьте, что клиентский сертификат в базе данных совпадает с тем,"
echo "        что установлен на ноде (SSL_CLIENT_CERT_FILE)"
echo ""
echo "   📋 Проверьте на ноде:"
echo "      docker exec anomaly-node cat /var/lib/marzban-node/ssl/certificate.pem | head -5"
echo "      docker exec anomaly-node env | grep SSL_CLIENT_CERT"
echo ""

echo "✅ Тест завершен!"
echo ""


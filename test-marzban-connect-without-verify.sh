#!/bin/bash
# Тест подключения Marzban к ноде БЕЗ проверки сертификата сервера

echo "🔍 Тест подключения Marzban к ноде БЕЗ проверки сертификата сервера"
echo "==================================================================="
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

echo "1️⃣  Тест подключения с клиентским сертификатом, БЕЗ проверки сертификата сервера..."
CONNECTION_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
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
    
    # Создать сессию БЕЗ проверки сертификата сервера
    from app.xray.node import SANIgnoringAdaptor
    session = requests.Session()
    session.mount('https://', SANIgnoringAdaptor())
    session.cert = (client_cert_file.name, client_key_file.name)
    session.verify = False  # НЕ проверять сертификат сервера
    
    # Попробовать подключиться
    connect_url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    print(f'INFO: Connecting to {connect_url}...')
    print(f'INFO: Using client cert: {client_cert_file.name}')
    print(f'INFO: verify=False (not checking server certificate)')
    
    try:
        response = session.post(connect_url, json={'session_id': None}, timeout=10)
        if response.status_code == 200:
            data = response.json()
            session_id = data.get('session_id', 'N/A')
            print(f'SUCCESS: Connected, Session ID: {session_id[:30]}...')
            
            # Попробовать проверить статус через /
            root_url = f'https://{NODE_IP}:{NODE_PORT}/'
            root_response = session.post(root_url, json={'session_id': session_id}, timeout=5)
            if root_response.status_code == 200:
                status_data = root_response.json()
                started = status_data.get('started', False)
                print(f'STATUS: Xray core started={started}')
        else:
            print(f'ERROR: HTTP {response.status_code}')
            print(f'Response: {response.text[:200]}')
    except requests.exceptions.SSLError as e:
        print(f'SSL_ERROR: {str(e)[:300]}')
    except requests.exceptions.ConnectionError as e:
        print(f'CONNECTION_ERROR: {str(e)[:300]}')
        import traceback
        traceback.print_exc()
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
echo "2️⃣  Анализ проблемы:"
echo "   💡 Если подключение с verify=False работает, но с verify=server_cert не работает:"
echo "      - Проблема в том, как Marzban проверяет сертификат сервера"
echo "      - Возможно, нужно модифицировать код Marzban, чтобы использовать verify=False"
echo "      - Или нужно исправить сертификат сервера на ноде"
echo ""

echo "✅ Тест завершен!"
echo ""


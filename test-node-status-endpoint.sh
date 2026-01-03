#!/bin/bash
# Тест статуса ноды через / endpoint (как проверяет Marzban)

echo "🔍 Тест статуса ноды через / endpoint"
echo "======================================"
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

echo "1️⃣  Тест получения статуса ноды через / endpoint..."
STATUS_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import ssl
import requests
import tempfile
import json
import urllib3

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT

try:
    from app.db import GetDB
    from app.db.models import TLS
    
    # Получить клиентский сертификат из базы данных
    with GetDB() as db:
        tls = db.query(TLS).first()
        if not tls:
            print('ERROR: TLS certificate not found')
            sys.exit(1)
        
        # Создать временные файлы
        cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        
        cert_file.write(tls.certificate)
        cert_file.flush()
        
        key_file.write(tls.key)
        key_file.flush()
    
    # Получить сертификат сервера
    server_cert = ssl.get_server_certificate((NODE_IP, NODE_PORT))
    server_cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
    server_cert_file.write(server_cert)
    server_cert_file.flush()
    
    # Создать сессию с клиентским сертификатом
    # Отключаем проверку hostname (сертификат выдан для 'Gozargah', а не для IP)
    import urllib3
    urllib3.disable_warnings()
    
    # Создать SSL context без проверки hostname
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    
    session = requests.Session()
    session.verify = False  # Отключаем проверку сертификата сервера
    session.cert = (cert_file.name, key_file.name)
    
    # Использовать SSL context без проверки hostname
    from requests.adapters import HTTPAdapter
    from urllib3.poolmanager import PoolManager
    
    class NoHostnameCheckAdapter(HTTPAdapter):
        def init_poolmanager(self, *args, **kwargs):
            kwargs['ssl_context'] = ssl_context
            return super().init_poolmanager(*args, **kwargs)
    
    session.mount('https://', NoHostnameCheckAdapter())
    
    # Подключиться к /connect
    connect_url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    connect_response = session.post(connect_url, json={'session_id': None}, timeout=5)
    
    if connect_response.status_code != 200:
        print(f'ERROR: /connect failed - HTTP {connect_response.status_code}')
        sys.exit(1)
    
    session_id = connect_response.json().get('session_id')
    print(f'SUCCESS: Connected, Session ID: {session_id[:30]}...')
    
    # Проверить статус через /
    root_url = f'https://{NODE_IP}:{NODE_PORT}/'
    root_response = session.post(root_url, json={'session_id': session_id}, timeout=5)
    
    if root_response.status_code == 200:
        status_data = root_response.json()
        print(f'SUCCESS: / endpoint - HTTP 200')
        print(f'Response: {json.dumps(status_data, indent=2)[:500]}')
        
        started = status_data.get('started', False)
        if started:
            print('STATUS: Xray core is STARTED')
        else:
            print('STATUS: Xray core is NOT STARTED')
            print('REASON: Marzban should send /start request, but it may not be doing so')
    else:
        print(f'ERROR: / endpoint failed - HTTP {root_response.status_code}')
        print(f'Response: {root_response.text[:200]}')
        
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | grep -v "UserWarning" | grep -v "InsecureRequestWarning")

if echo "$STATUS_TEST" | grep -q "SUCCESS.*Connected"; then
    echo "   ✅ Подключение успешно"
    echo "$STATUS_TEST" | sed 's/^/      /'
else
    echo "   ❌ Подключение не удалось:"
    echo "$STATUS_TEST" | sed 's/^/      /'
fi

echo ""
echo "✅ Тест завершен!"
echo ""


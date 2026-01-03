#!/bin/bash
# Детальная диагностика подключения Marzban к ноде

echo "🔍 Детальная диагностика подключения Marzban к ноде"
echo "=================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка последних ошибок подключения в логах Marzban..."
echo "   📋 Поиск ошибок и исключений:"
docker logs anomaly-marzban --tail 200 2>&1 | grep -i -E "(error|exception|traceback|failed|ssl|certificate|hostname|connection.*aborted)" | tail -30 | sed 's/^/      /' || echo "      ℹ️  Нет явных ошибок в последних логах"

echo ""
echo "2️⃣  Проверка попыток подключения к ноде..."
echo "   📋 Последние попытки подключения:"
docker logs anomaly-marzban --tail 100 2>&1 | grep -E "(Connecting|Unable to connect|node)" | tail -10 | sed 's/^/      /'

echo ""
echo "3️⃣  Проверка конфигурации ноды в базе данных..."
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node, TLS

try:
    with GetDB() as db:
        node = db.query(Node).first()
        if not node:
            print('ERROR: Node not found')
            sys.exit(1)
        
        print(f'Node name: {node.name}')
        print(f'Node address: {node.address}')
        print(f'Node port: {node.port}')
        print(f'Node status: {node.status if hasattr(node, \"status\") else \"N/A\"}')
        
        tls = db.query(TLS).first()
        if tls:
            cert_preview = tls.certificate.split('\n')[1][:50] if len(tls.certificate) > 50 else 'N/A'
            print(f'TLS cert preview: {cert_preview}...')
            print(f'TLS cert length: {len(tls.certificate)}')
            print(f'TLS key length: {len(tls.key)}')
        else:
            print('ERROR: TLS certificate not found')
            
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
" 2>&1 | grep -v "UserWarning")

echo "$NODE_INFO" | sed 's/^/      /'

echo ""
echo "4️⃣  Тест подключения с использованием того же метода, что и Marzban..."
echo "   📋 Симуляция подключения Marzban к ноде:"
CONNECTION_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import requests
import ssl
import tempfile
import json

NODE_IP = '185.126.67.67'
NODE_PORT = 62050

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
    
    # Попробовать найти SANIgnoringAdaptor (как в Marzban)
    try:
        from app.xray.node import SANIgnoringAdaptor
        use_san_adaptor = True
    except ImportError:
        use_san_adaptor = False
        print('INFO: SANIgnoringAdaptor not found, using standard adapter')
    
    # Создать сессию как Marzban
    session = requests.Session()
    
    if use_san_adaptor:
        session.mount('https://', SANIgnoringAdaptor())
        print('INFO: Using SANIgnoringAdaptor')
    else:
        # Отключить проверку hostname вручную
        import urllib3
        urllib3.disable_warnings()
        session.verify = False
        print('INFO: Using verify=False')
    
    session.cert = (cert_file.name, key_file.name)
    
    # Попробовать подключиться к /connect
    connect_url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    print(f'INFO: Connecting to {connect_url}')
    
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
    print(f'SETUP_ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
" 2>&1 | grep -v "UserWarning" | grep -v "InsecureRequestWarning")

echo "$CONNECTION_TEST" | sed 's/^/      /'

echo ""
echo "5️⃣  Рекомендации:"
echo "   💡 Если подключение не удается:"
echo "      1. Проверьте, что нода доступна: curl -k https://185.126.67.67:62050/ping"
echo "      2. Проверьте логи ноды: docker logs anomaly-node --tail 50"
echo "      3. Убедитесь, что сертификат в базе данных совпадает с сертификатом на ноде"
echo "      4. Попробуйте перегенерировать сертификат в панели Marzban"
echo ""


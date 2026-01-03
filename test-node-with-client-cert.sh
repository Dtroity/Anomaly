#!/bin/bash
# Тест подключения к ноде с клиентским сертификатом (как Marzban)

echo "🔍 Тест подключения к ноде с клиентским сертификатом"
echo "===================================================="
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

echo "1️⃣  Получение клиентского сертификата из базы данных Marzban..."
CERT_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

with GetDB() as db:
    tls = db.query(TLS).first()
    if tls:
        # Сохранить сертификат и ключ во временные файлы
        import tempfile
        cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        
        cert_file.write(tls.certificate)
        cert_file.flush()
        
        key_file.write(tls.key)
        key_file.flush()
        
        print(f'CERT_FILE={cert_file.name}')
        print(f'KEY_FILE={key_file.name}')
        print(f'CERT_LENGTH={len(tls.certificate)}')
        print(f'KEY_LENGTH={len(tls.key)}')
    else:
        print('ERROR: TLS certificate not found in database')
        sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$CERT_INFO" | grep -q "ERROR"; then
    echo "   ❌ $CERT_INFO"
    exit 1
fi

CERT_FILE=$(echo "$CERT_INFO" | grep "CERT_FILE=" | cut -d'=' -f2)
KEY_FILE=$(echo "$CERT_INFO" | grep "KEY_FILE=" | cut -d'=' -f2)

if [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
    echo "   ❌ Не удалось получить пути к сертификатам"
    exit 1
fi

echo "   ✅ Сертификат получен из базы данных"
echo "      Cert: $CERT_FILE"
echo "      Key: $KEY_FILE"

echo ""
echo "2️⃣  Тест подключения с клиентским сертификатом (как Marzban)..."
CONNECTION_TEST=$(docker exec anomaly-marzban python3 -c "
import requests
import ssl
import sys

NODE_IP = '$NODE_IP'
NODE_PORT = $NODE_PORT
CERT_FILE = '$CERT_FILE'
KEY_FILE = '$KEY_FILE'

try:
    # Создать сессию с клиентским сертификатом (как Marzban)
    session = requests.Session()
    session.verify = False  # Отключить проверку сертификата сервера
    session.cert = (CERT_FILE, KEY_FILE)
    
    # Попробовать подключиться к /connect (как делает Marzban)
    url = f'https://{NODE_IP}:{NODE_PORT}/connect'
    data = {'session_id': None}
    
    try:
        response = session.post(url, json=data, timeout=10, verify=False)
        print(f'SUCCESS: HTTP {response.status_code}')
        print(f'Response: {response.text[:200]}')
    except requests.exceptions.SSLError as e:
        print(f'SSL_ERROR: {str(e)[:300]}')
        sys.exit(1)
    except requests.exceptions.ConnectionError as e:
        print(f'CONNECTION_ERROR: {str(e)[:300]}')
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f'REQUEST_ERROR: {type(e).__name__}: {str(e)[:300]}')
        sys.exit(1)
    except Exception as e:
        print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
        sys.exit(1)
        
except Exception as e:
    print(f'SETUP_ERROR: {type(e).__name__}: {str(e)[:300]}')
    sys.exit(1)
" 2>&1)

if echo "$CONNECTION_TEST" | grep -q "SUCCESS"; then
    echo "   ✅ Подключение успешно!"
    echo "$CONNECTION_TEST" | sed 's/^/      /'
else
    echo "   ❌ Подключение не удалось:"
    echo "$CONNECTION_TEST" | sed 's/^/      /'
fi

echo ""
echo "✅ Тест завершен!"
echo ""

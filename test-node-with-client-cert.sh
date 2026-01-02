#!/bin/bash
# Тест подключения к ноде с клиентским SSL сертификатом (как Marzban)

echo "🔍 Тест подключения к ноде с клиентским сертификатом"
echo "===================================================="
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

# Найти клиентский сертификат
CLIENT_CERT=""
CLIENT_KEY=""

# Проверить в разных местах
if [ -f "/var/lib/marzban/ssl/certificate.pem" ]; then
    CLIENT_CERT="/var/lib/marzban/ssl/certificate.pem"
    CLIENT_KEY="/var/lib/marzban/ssl/key.pem"
elif [ -f "marzban_data/ssl/certificate.pem" ]; then
    CLIENT_CERT="marzban_data/ssl/certificate.pem"
    CLIENT_KEY="marzban_data/ssl/key.pem"
elif [ -f "node-certs/ssl_client_cert.pem" ]; then
    CLIENT_CERT="node-certs/ssl_client_cert.pem"
    CLIENT_KEY="node-certs/ssl_client_key.pem"
fi

if [ -z "$CLIENT_CERT" ] || [ ! -f "$CLIENT_CERT" ]; then
    echo "❌ Клиентский сертификат не найден"
    echo ""
    echo "💡 Проверьте наличие сертификата:"
    echo "   docker exec anomaly-marzban ls -la /var/lib/marzban/ssl/"
    echo "   или"
    echo "   ls -la marzban_data/ssl/"
    exit 1
fi

echo "✅ Клиентский сертификат найден: $CLIENT_CERT"
if [ -f "$CLIENT_KEY" ]; then
    echo "✅ Клиентский ключ найден: $CLIENT_KEY"
else
    echo "⚠️  Клиентский ключ не найден: $CLIENT_KEY"
fi

echo ""
echo "📡 Тест подключения с клиентским сертификатом (как Marzban)..."
echo ""

# Тест 1: POST /connect с клиентским сертификатом
echo "1️⃣  Тест: POST /connect с клиентским сертификатом"
CONNECT_TEST=$(docker exec -i anomaly-marzban python3 << 'PYTHON_SCRIPT'
import requests
import ssl
import json
import sys

NODE_IP = "185.126.67.67"
NODE_PORT = "62050"

# Попробовать найти сертификат внутри контейнера
cert_paths = [
    "/var/lib/marzban/ssl/certificate.pem",
    "/var/lib/marzban/ssl/key.pem",
]

try:
    import os
    cert_file = None
    key_file = None
    
    for path in cert_paths:
        if os.path.exists(path):
            if "certificate" in path:
                cert_file = path
            elif "key" in path:
                key_file = path
    
    if not cert_file or not key_file:
        print("ERROR: Certificate files not found in container")
        sys.exit(1)
    
    # Создать сессию с клиентским сертификатом
    session = requests.Session()
    session.verify = False  # Отключить проверку сертификата сервера
    session.cert = (cert_file, key_file)
    
    # Попробовать подключиться
    url = f"https://{NODE_IP}:{NODE_PORT}/connect"
    data = {"session_id": None}
    
    try:
        response = session.post(url, json=data, timeout=10, verify=False)
        print(f"SUCCESS: HTTP {response.status_code} - {response.text[:200]}")
    except requests.exceptions.SSLError as e:
        print(f"SSL_ERROR: {str(e)[:200]}")
    except requests.exceptions.RequestException as e:
        print(f"REQUEST_ERROR: {str(e)[:200]}")
    except Exception as e:
        print(f"ERROR: {type(e).__name__}: {str(e)[:200]}")
        
except Exception as e:
    print(f"SETUP_ERROR: {str(e)[:200]}")
PYTHON_SCRIPT
)
echo "$CONNECT_TEST"
echo ""

# Тест 2: POST /ping с клиентским сертификатом
echo "2️⃣  Тест: POST /ping с клиентским сертификатом"
PING_TEST=$(docker exec -i anomaly-marzban python3 << 'PYTHON_SCRIPT'
import requests
import os

NODE_IP = "185.126.67.67"
NODE_PORT = "62050"

cert_paths = [
    "/var/lib/marzban/ssl/certificate.pem",
    "/var/lib/marzban/ssl/key.pem",
]

try:
    cert_file = None
    key_file = None
    
    for path in cert_paths:
        if os.path.exists(path):
            if "certificate" in path:
                cert_file = path
            elif "key" in path:
                key_file = path
    
    if not cert_file or not key_file:
        print("ERROR: Certificate files not found")
    else:
        session = requests.Session()
        session.verify = False
        session.cert = (cert_file, key_file)
        
        url = f"https://{NODE_IP}:{NODE_PORT}/ping"
        data = {"session_id": None}
        
        try:
            response = session.post(url, json=data, timeout=10, verify=False)
            print(f"SUCCESS: HTTP {response.status_code} - {response.text[:200]}")
        except Exception as e:
            print(f"ERROR: {type(e).__name__}: {str(e)[:200]}")
except Exception as e:
    print(f"ERROR: {str(e)[:200]}")
PYTHON_SCRIPT
)
echo "$PING_TEST"
echo ""

echo "📋 Проверка сертификатов внутри контейнера Marzban:"
docker exec anomaly-marzban ls -la /var/lib/marzban/ssl/ 2>/dev/null || echo "  ⚠️  Директория не найдена"

echo ""
echo "✅ Тест завершен"
echo ""


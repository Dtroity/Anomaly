#!/bin/bash
# Проверка доступных endpoints на ноде

echo "🔍 Проверка endpoints на ноде"
echo "============================="
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "📡 Тест различных endpoints на ноде..."
echo ""

# Тест 1: Корневой endpoint
echo "1️⃣  Тест: GET /"
RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        print(f'SUCCESS: {resp.getcode()} - {resp.read().decode()[:200]}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $RESPONSE"
echo ""

# Тест 2: /connect endpoint
echo "2️⃣  Тест: POST /connect"
CONNECT_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request, json, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/connect', method='POST')
    req.add_header('Content-Type', 'application/json')
    data = json.dumps({}).encode()
    with urllib.request.urlopen(req, data=data, timeout=5, context=ssl_context) as resp:
        print(f'SUCCESS: {resp.getcode()} - {resp.read().decode()[:200]}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $CONNECT_RESPONSE"
echo ""

# Тест 3: /health endpoint
echo "3️⃣  Тест: GET /health"
HEALTH_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/health')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        print(f'SUCCESS: {resp.getcode()} - {resp.read().decode()[:200]}')
except Exception as e:
        print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $HEALTH_RESPONSE"
echo ""

# Тест 4: /api/status endpoint
echo "4️⃣  Тест: GET /api/status"
API_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/api/status')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        print(f'SUCCESS: {resp.getcode()} - {resp.read().decode()[:200]}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $API_RESPONSE"
echo ""

# Тест 5: Проверка с правильными заголовками (как Marzban)
echo "5️⃣  Тест: GET / с заголовками Marzban"
MARZBAN_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/')
    req.add_header('User-Agent', 'Marzban/1.0')
    req.add_header('Accept', 'application/json')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        print(f'SUCCESS: {resp.getcode()} - Headers: {dict(resp.getheaders())[:5]}')
except Exception as e:
    print(f'ERROR: {str(e)}')
" 2>/dev/null)
echo "   $MARZBAN_RESPONSE"
echo ""

echo "📋 Проверка логов ноды (последние 20 строк):"
echo "   Выполните на Node Server:"
echo "   ssh root@$NODE_IP 'docker logs anomaly-node --tail=20'"
echo ""

echo "✅ Тест завершен"
echo ""


#!/bin/bash
# Тест подключения к ноде с Control Server с детальной диагностикой

echo "🔍 Детальный тест подключения к ноде"
echo "===================================="
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"

echo "📡 Тест 1: Проверка доступности порта..."
if timeout 3 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "  ✅ Порт $NODE_PORT открыт"
else
    echo "  ❌ Порт $NODE_PORT недоступен"
    exit 1
fi

echo ""
echo "📡 Тест 2: HTTPS подключение с детальным выводом..."
HTTPS_DETAIL=$(timeout 10 openssl s_client -connect "$NODE_IP:$NODE_PORT" -servername "$NODE_IP" </dev/null 2>&1)
if echo "$HTTPS_DETAIL" | grep -q "CONNECTED"; then
    echo "  ✅ HTTPS подключение установлено"
    echo "$HTTPS_DETAIL" | grep -E "Verify return code|Protocol|Cipher" | head -5 | sed 's/^/    /'
else
    echo "  ❌ HTTPS подключение не установлено"
    echo "$HTTPS_DETAIL" | grep -E "error|failed" | head -5 | sed 's/^/    /'
fi

echo ""
echo "📡 Тест 3: HTTP запрос к корневому endpoint..."
ROOT_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl, socket
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT/')
    req.add_header('User-Agent', 'Marzban/1.0')
    req.add_header('Accept', '*/*')
    with urllib.request.urlopen(req, timeout=10, context=ssl_context) as resp:
        status = resp.getcode()
        headers = dict(resp.getheaders())
        body = resp.read().decode()[:500]
        print(f'SUCCESS: HTTP {status}')
        print(f'Headers: {list(headers.keys())[:5]}')
        print(f'Body: {body[:200]}')
except urllib.error.HTTPError as e:
    print(f'HTTP_ERROR: {e.code} - {e.read().decode()[:200]}')
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)}')
" 2>/dev/null)
echo "$ROOT_TEST" | sed 's/^/  /'

echo ""
echo "📡 Тест 4: Проверка различных endpoints..."
ENDPOINTS=("/" "/health" "/api/status" "/connect" "/api/system")
for endpoint in "${ENDPOINTS[@]}"; do
    echo "  Тест: GET $endpoint"
    ENDPOINT_TEST=$(docker exec anomaly-marzban python3 -c "
import urllib.request, ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
try:
    req = urllib.request.Request('https://$NODE_IP:$NODE_PORT$endpoint')
    req.add_header('User-Agent', 'Marzban/1.0')
    with urllib.request.urlopen(req, timeout=5, context=ssl_context) as resp:
        print(f'SUCCESS: {resp.getcode()}')
except urllib.error.HTTPError as e:
    print(f'HTTP_ERROR: {e.code}')
except Exception as e:
    print(f'ERROR: {str(e)[:100]}')
" 2>/dev/null)
    echo "    $ENDPOINT_TEST"
done

echo ""
echo "📡 Тест 5: Проверка через curl (если доступен)..."
if command -v curl >/dev/null 2>&1; then
    CURL_TEST=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$NODE_IP:$NODE_PORT/" 2>&1)
    if [ "$CURL_TEST" != "000" ] && [ "$CURL_TEST" != "" ]; then
        echo "  ✅ curl подключение: HTTP $CURL_TEST"
    else
        echo "  ❌ curl подключение не удалось"
    fi
else
    echo "  ⚠️  curl не установлен"
fi

echo ""
echo "📋 Проверка логов Marzban (последние 20 строк с упоминанием ноды):"
docker logs anomaly-marzban --tail=100 2>&1 | grep -i -E "node|185.126.67.67|connection|connect" | tail -20 | sed 's/^/   /'

echo ""
echo "✅ Тест завершен"
echo ""
echo "💡 Если все тесты показывают ошибки:"
echo "   1. Проверьте логи ноды: ssh root@$NODE_IP 'docker logs anomaly-node --tail=50'"
echo "   2. Проверьте, что нода слушает на 0.0.0.0, а не на 127.0.0.1"
echo "   3. Проверьте firewall на ноде: ufw status или iptables -L"
echo ""


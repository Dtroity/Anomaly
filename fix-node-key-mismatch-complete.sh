#!/bin/bash

# Полное исправление проблемы KEY_VALUES_MISMATCH для ноды Marzban

echo "🔧 Полное исправление KEY_VALUES_MISMATCH для ноды"
echo "=================================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"

echo "📋 Параметры ноды:"
echo "   IP: $NODE_IP"
echo ""

# Получение токена админа
echo "1️⃣  Получение токена админа..."
ADMIN_USERNAME=$(grep -E "^SUDO_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || grep -E "^ADMIN_USERNAME=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
ADMIN_PASSWORD=$(grep -E "^SUDO_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || grep -E "^ADMIN_PASSWORD=" .env.marzban 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "❌ Не удалось найти учетные данные админа в .env.marzban"
    exit 1
fi

TOKEN=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import urllib.parse
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

data = urllib.parse.urlencode({'username': '$ADMIN_USERNAME', 'password': '$ADMIN_PASSWORD'}).encode()
req = urllib.request.Request('http://marzban:62050/api/admin/token', data=data)
req.add_header('Content-Type', 'application/x-www-form-urlencoded')

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode())
        print(result.get('access_token', ''))
except Exception as e:
    print('')
" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен админа"
    exit 1
fi

echo "✅ Токен получен"
echo ""

# Получение информации о ноде
echo "2️⃣  Получение информации о ноде..."
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://marzban:62050/api/nodes')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req) as response:
        nodes = json.loads(response.read().decode())
        if isinstance(nodes, dict) and 'nodes' in nodes:
            nodes = nodes['nodes']
        if nodes and len(nodes) > 0:
            node = nodes[0]
            print(json.dumps({
                'id': node.get('id'),
                'name': node.get('name'),
                'address': node.get('address'),
                'port': node.get('port'),
                'api_port': node.get('api_port')
            }))
        else:
            print('{}')
except Exception as e:
    print('{}')
" 2>/dev/null)

if [ "$NODE_INFO" = "{}" ]; then
    echo "❌ Нода не найдена в Marzban"
    exit 1
fi

NODE_ID=$(echo "$NODE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
NODE_NAME=$(echo "$NODE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null)

echo "   Найдена нода: $NODE_NAME (ID: $NODE_ID)"
echo ""

# Скачивание сертификата из панели
echo "3️⃣  Скачивание сертификата из панели Marzban..."
CERT_CONTENT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://marzban:62050/api/node/$NODE_ID/certificate')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode())
        print(result.get('certificate', ''))
except Exception as e:
    print('')
" 2>/dev/null)

if [ -z "$CERT_CONTENT" ] || [ ! "$(echo "$CERT_CONTENT" | grep -c "BEGIN CERTIFICATE")" -gt 0 ]; then
    echo "❌ Не удалось скачать сертификат из панели"
    exit 1
fi

echo "✅ Сертификат скачан"
echo ""

# Сохранение сертификата во временный файл
TEMP_CERT="/tmp/node-cert-from-panel-$(date +%s).pem"
echo "$CERT_CONTENT" > "$TEMP_CERT"

echo "4️⃣  Установка сертификата на ноду..."
ssh root@$NODE_IP "docker exec anomaly-node sh -c 'cat > /var/lib/marzban-node/ssl/certificate.pem'" < "$TEMP_CERT" 2>&1 | grep -v "password:"

if [ $? -eq 0 ]; then
    echo "✅ Сертификат установлен на ноде"
else
    echo "❌ Ошибка при установке сертификата на ноду"
    exit 1
fi

echo ""

# Перезапуск ноды
echo "5️⃣  Перезапуск ноды..."
ssh root@$NODE_IP "cd /opt/Anomaly && docker-compose -f docker-compose.node.yml restart anomaly-node" 2>&1 | grep -v "password:"

echo "   ⏳ Ожидание запуска (10 секунд)..."
sleep 10

echo ""

# Синхронизация сертификата и ключа с ноды в базу данных
echo "6️⃣  Синхронизация сертификата и ключа с ноды в базу данных..."
./sync-cert-and-key-from-node.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Синхронизация завершена"
else
    echo ""
    echo "⚠️  Ошибка при синхронизации, но продолжаем..."
fi

echo ""

# Перезапуск Marzban для применения изменений
echo "7️⃣  Перезапуск Marzban..."
docker-compose restart marzban

echo "   ⏳ Ожидание запуска (10 секунд)..."
sleep 10

echo ""

# Проверка статуса ноды
echo "8️⃣  Проверка статуса ноды..."
sleep 5

NODE_STATUS=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

req = urllib.request.Request('http://marzban:62050/api/nodes')
req.add_header('Authorization', 'Bearer $TOKEN')

try:
    with urllib.request.urlopen(req) as response:
        nodes = json.loads(response.read().decode())
        if isinstance(nodes, dict) and 'nodes' in nodes:
            nodes = nodes['nodes']
        if nodes and len(nodes) > 0:
            node = nodes[0]
            print(f\"Status: {node.get('status', 'unknown')}, Message: {node.get('message', 'none')}\")
        else:
            print('No nodes found')
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null)

echo "   $NODE_STATUS"
echo ""

# Очистка временных файлов
rm -f "$TEMP_CERT"

echo "✅ Исправление завершено!"
echo ""
echo "💡 Если ошибка все еще присутствует:"
echo "   1. Подождите 30-60 секунд для полной синхронизации"
echo "   2. Нажмите 'Переподключиться' в панели Marzban"
echo "   3. Проверьте логи ноды: ssh root@$NODE_IP 'docker-compose -f /opt/Anomaly/docker-compose.node.yml logs anomaly-node --tail=50'"


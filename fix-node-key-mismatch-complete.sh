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

# Проверка наличия файла .env.marzban
if [ ! -f ".env.marzban" ]; then
    echo "❌ Файл .env.marzban не найден"
    echo "   Проверяю альтернативные пути..."
    if [ -f "marzban/.env.marzban" ]; then
        ENV_FILE="marzban/.env.marzban"
    elif [ -f ".env" ]; then
        ENV_FILE=".env"
    else
        echo "❌ Не удалось найти файл с переменными окружения"
        exit 1
    fi
else
    ENV_FILE=".env.marzban"
fi

echo "   Используется файл: $ENV_FILE"

ADMIN_USERNAME=$(grep -E "^SUDO_USERNAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)
if [ -z "$ADMIN_USERNAME" ]; then
    ADMIN_USERNAME=$(grep -E "^ADMIN_USERNAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)
fi

ADMIN_PASSWORD=$(grep -E "^SUDO_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(grep -E "^ADMIN_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)
fi

# Попробуем получить из переменных окружения контейнера
if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "   Пробую получить из переменных окружения контейнера..."
    ADMIN_USERNAME=$(docker exec anomaly-marzban env | grep -E "^SUDO_USERNAME=" | cut -d'=' -f2 | head -1)
    if [ -z "$ADMIN_USERNAME" ]; then
        ADMIN_USERNAME=$(docker exec anomaly-marzban env | grep -E "^ADMIN_USERNAME=" | cut -d'=' -f2 | head -1)
    fi
    
    ADMIN_PASSWORD=$(docker exec anomaly-marzban env | grep -E "^SUDO_PASSWORD=" | cut -d'=' -f2 | head -1)
    if [ -z "$ADMIN_PASSWORD" ]; then
        ADMIN_PASSWORD=$(docker exec anomaly-marzban env | grep -E "^ADMIN_PASSWORD=" | cut -d'=' -f2 | head -1)
    fi
fi

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "❌ Не удалось найти учетные данные админа"
    echo ""
    echo "💡 Попробуйте указать вручную:"
    echo "   export ADMIN_USERNAME='ваш_username'"
    echo "   export ADMIN_PASSWORD='ваш_password'"
    echo "   ./fix-node-key-mismatch-complete.sh"
    echo ""
    echo "   Или проверьте файл $ENV_FILE"
    exit 1
fi

echo "   ✅ Учетные данные найдены (username: ${ADMIN_USERNAME:0:3}...)"

# Проверка доступности Marzban и ожидание полного запуска
echo "   Проверка доступности Marzban..."
MAX_RETRIES=10
RETRY_COUNT=0
MARZBAN_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec anomaly-marzban python3 -c "
import urllib.request
import ssl
ssl._create_default_https_context = ssl._create_unverified_context
try:
    with urllib.request.urlopen('http://localhost:62050/api/system', timeout=5) as response:
        if response.status == 200:
            exit(0)
except:
    exit(1)
" 2>/dev/null; then
        MARZBAN_READY=true
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "   ⏳ Ожидание запуска Marzban... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ "$MARZBAN_READY" = "false" ]; then
    echo "   ⚠️  Marzban может быть недоступен, но продолжаем попытку..."
fi

# Попытка получить токен с несколькими попытками
TOKEN=""
MAX_TOKEN_RETRIES=3
TOKEN_RETRY=0

while [ $TOKEN_RETRY -lt $MAX_TOKEN_RETRIES ] && [ -z "$TOKEN" ]; do
    if [ $TOKEN_RETRY -gt 0 ]; then
        echo "   ⏳ Повторная попытка получения токена... ($TOKEN_RETRY/$MAX_TOKEN_RETRIES)"
        sleep 2
    fi
    
    TOKEN=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import urllib.parse
import json
import ssl
import sys

ssl._create_default_https_context = ssl._create_unverified_context

username = '$ADMIN_USERNAME'
password = '$ADMIN_PASSWORD'

data = urllib.parse.urlencode({'username': username, 'password': password}).encode()
req = urllib.request.Request('http://marzban:62050/api/admin/token', data=data)
req.add_header('Content-Type', 'application/x-www-form-urlencoded')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        if response.status == 200:
            result = json.loads(response.read().decode())
            token = result.get('access_token', '')
            if token:
                print(token)
            else:
                print('ERROR: Token not found in response', file=sys.stderr)
                sys.exit(1)
        else:
            error_text = response.read().decode()
            print(f'ERROR: HTTP {response.status}: {error_text[:200]}', file=sys.stderr)
            sys.exit(1)
except urllib.error.HTTPError as e:
    error_text = e.read().decode() if hasattr(e, 'read') else str(e)
    print(f'ERROR: HTTP {e.code}: {error_text[:200]}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:200]}', file=sys.stderr)
    sys.exit(1)
" 2>&1)
    
    TOKEN_RETRY=$((TOKEN_RETRY + 1))
done

if [ -z "$TOKEN" ]; then
    echo "❌ Не удалось получить токен админа после $MAX_TOKEN_RETRIES попыток"
    echo ""
    echo "💡 Попробуйте получить токен вручную:"
    echo "   docker exec anomaly-marzban python3 -c \\"
    echo "   \""
    echo "   import urllib.request"
    echo "   import urllib.parse"
    echo "   import json"
    echo "   import ssl"
    echo "   ssl._create_default_https_context = ssl._create_unverified_context"
    echo "   data = urllib.parse.urlencode({'username': '$ADMIN_USERNAME', 'password': '$ADMIN_PASSWORD'}).encode()"
    echo "   req = urllib.request.Request('http://marzban:62050/api/admin/token', data=data)"
    echo "   req.add_header('Content-Type', 'application/x-www-form-urlencoded')"
    echo "   with urllib.request.urlopen(req) as response:"
    echo "       print(json.loads(response.read().decode()).get('access_token', ''))"
    echo "   \""
    echo ""
    echo "💡 Или проверьте:"
    echo "   1. Правильность учетных данных в $ENV_FILE"
    echo "   2. Статус Marzban: docker-compose ps marzban"
    echo "   3. Логи Marzban: docker-compose logs --tail=50 marzban | grep -i error"
    exit 1
fi

echo "✅ Токен получен"
echo ""

# Получение информации о ноде
echo "2️⃣  Получение информации о ноде..."

# Сначала пробуем получить через API
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl
import time

ssl._create_default_https_context = ssl._create_unverified_context

token = '$TOKEN'
max_retries = 3

for attempt in range(max_retries):
    try:
        req = urllib.request.Request('http://localhost:62050/api/nodes')
        req.add_header('Authorization', f'Bearer {token}')
        
        with urllib.request.urlopen(req, timeout=15) as response:
            response_data = response.read().decode()
            nodes = json.loads(response_data)
            
            # Обработка разных форматов ответа
            if isinstance(nodes, dict):
                if 'nodes' in nodes:
                    nodes = nodes['nodes']
                elif 'data' in nodes:
                    nodes = nodes['data']
            
            if isinstance(nodes, list) and len(nodes) > 0:
                # Ищем ноду по IP адресу или берем первую
                target_node = None
                for node in nodes:
                    if node.get('address') == '$NODE_IP':
                        target_node = node
                        break
                
                if not target_node:
                    target_node = nodes[0]
                
                print(json.dumps({
                    'id': target_node.get('id'),
                    'name': target_node.get('name'),
                    'address': target_node.get('address'),
                    'port': target_node.get('port'),
                    'api_port': target_node.get('api_port')
                }))
                exit(0)
    except Exception as e:
        if attempt < max_retries - 1:
            time.sleep(2)
            continue
        # Если API не работает, пробуем через базу данных
        pass

# Если API не работает, получаем через базу данных
try:
    import sys
    sys.path.insert(0, '/code')
    from app.db import GetDB
    from app.db.models import Node
    
    with GetDB() as db:
        node = db.query(Node).filter(Node.address == '$NODE_IP').first()
        if not node:
            node = db.query(Node).first()
        
        if node:
            print(json.dumps({
                'id': node.id,
                'name': node.name,
                'address': node.address,
                'port': node.port,
                'api_port': node.api_port
            }))
            exit(0)
except Exception as db_error:
    print('{}', file=__import__('sys').stderr)
    exit(1)
" 2>&1)

# Извлекаем только JSON
NODE_INFO=$(echo "$NODE_INFO" | grep -E '^\{' | head -1)

if [ "$NODE_INFO" = "{}" ] || [[ "$NODE_INFO" == ERROR* ]]; then
    echo "⚠️  Нода не найдена в Marzban"
    echo ""
    echo "💡 Создание ноды..."
    
    # Создаем ноду
    NODE_CREATE_RESULT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl

ssl._create_default_https_context = ssl._create_unverified_context

node_data = {
    'name': 'Node 1',
    'address': '$NODE_IP',
    'port': 62050,
    'api_port': 62051,
    'usage_coefficient': 1.0
}

data = json.dumps(node_data).encode()
req = urllib.request.Request('http://localhost:62050/api/node', data=data)
req.add_header('Authorization', 'Bearer $TOKEN')
req.add_header('Content-Type', 'application/json')

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        result = json.loads(response.read().decode())
        print(json.dumps({
            'id': result.get('id'),
            'name': result.get('name'),
            'address': result.get('address'),
            'port': result.get('port'),
            'api_port': result.get('api_port')
        }))
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    
    if [[ "$NODE_CREATE_RESULT" == ERROR* ]]; then
        echo "❌ Не удалось создать ноду: $NODE_CREATE_RESULT"
        exit 1
    fi
    
    NODE_INFO="$NODE_CREATE_RESULT"
    echo "✅ Нода создана"
    echo ""
fi

NODE_ID=$(echo "$NODE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
NODE_NAME=$(echo "$NODE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null)

if [ -z "$NODE_ID" ]; then
    echo "❌ Не удалось определить ID ноды"
    echo "   Ответ API: $NODE_INFO"
    exit 1
fi

echo "   Найдена нода: $NODE_NAME (ID: $NODE_ID)"
echo ""

# Скачивание сертификата из панели
echo "3️⃣  Скачивание сертификата из панели Marzban..."
CERT_CONTENT=$(docker exec anomaly-marzban python3 -c "
import urllib.request
import json
import ssl
import time

ssl._create_default_https_context = ssl._create_unverified_context

token = '$TOKEN'
node_id = $NODE_ID
max_retries = 3

for attempt in range(max_retries):
    try:
        req = urllib.request.Request(f'http://localhost:62050/api/node/{node_id}/certificate')
        req.add_header('Authorization', f'Bearer {token}')
        
        with urllib.request.urlopen(req, timeout=15) as response:
            if response.status == 200:
                result = json.loads(response.read().decode())
                cert = result.get('certificate', '')
                if cert and 'BEGIN CERTIFICATE' in cert:
                    print(cert)
                    exit(0)
                else:
                    print(f'ERROR: Invalid certificate format', file=__import__('sys').stderr)
            else:
                error_text = response.read().decode()
                print(f'ERROR: HTTP {response.status}: {error_text[:200]}', file=__import__('sys').stderr)
    except urllib.error.HTTPError as e:
        error_text = e.read().decode() if hasattr(e, 'read') else str(e)
        if attempt < max_retries - 1:
            time.sleep(2)
            continue
        print(f'ERROR: HTTP {e.code}: {error_text[:200]}', file=__import__('sys').stderr)
    except Exception as e:
        if attempt < max_retries - 1:
            time.sleep(2)
            continue
        print(f'ERROR: {type(e).__name__}: {str(e)[:200]}', file=__import__('sys').stderr)

exit(1)
" 2>&1)

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


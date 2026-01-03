#!/bin/bash
# Автоматическая настройка ноды через SSH
# Выполняется на Control Server (VPS #1)

set -e

echo "🚀 Автоматическая настройка ноды"
echo "================================="
echo ""

# Параметры
NODE_IP="${1:-185.126.67.67}"
NODE_USER="${2:-root}"
NODE_PASSWORD="${3:-}"
NODE_NAME="${4:-Node 1}"
NODE_PORT="${5:-62050}"
API_PORT="${6:-62051}"
CONTROL_SERVER_URL="${7:-https://panel.anomaly-connect.online}"

# Проверка SSH подключения без пароля (SSH ключи)
if [ -z "$NODE_PASSWORD" ]; then
    echo "ℹ️  Пароль не указан, проверяю SSH ключи..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$NODE_USER@$NODE_IP" "echo 'SSH key connection successful'" 2>/dev/null | grep -q "SSH key connection successful"; then
        echo "   ✅ SSH ключи настроены, пароль не требуется"
        USE_SSHPASS=false
    else
        echo "   ❌ SSH ключи не настроены, требуется пароль"
        echo ""
        echo "Использование:"
        echo "  $0 <NODE_IP> <NODE_USER> <NODE_PASSWORD> [NODE_NAME] [NODE_PORT] [API_PORT] [CONTROL_SERVER_URL]"
        echo ""
        echo "Пример:"
        echo "  $0 185.126.67.67 root MyPassword123 'Node 1' 62050 62051 https://panel.anomaly-connect.online"
        echo ""
        echo "Или настройте SSH ключи:"
        echo "  ssh-copy-id $NODE_USER@$NODE_IP"
        exit 1
    fi
else
    USE_SSHPASS=true
fi

echo "📋 Параметры:"
echo "   NODE_IP: $NODE_IP"
echo "   NODE_USER: $NODE_USER"
echo "   NODE_NAME: $NODE_NAME"
echo "   NODE_PORT: $NODE_PORT"
echo "   API_PORT: $API_PORT"
echo "   CONTROL_SERVER_URL: $CONTROL_SERVER_URL"
echo ""

# 1. Получение сертификата из Marzban
echo "1️⃣  Получение сертификата из Marzban..."
CERTIFICATE=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            print(tls.certificate)
        else:
            print('ERROR: TLS certificate not found')
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$CERTIFICATE" | grep -q "BEGIN CERTIFICATE"; then
    echo "   ✅ Сертификат получен"
else
    echo "   ❌ Не удалось получить сертификат"
    echo "$CERTIFICATE" | sed 's/^/      /'
    exit 1
fi

# 2. Проверка SSH подключения
echo ""
echo "2️⃣  Проверка SSH подключения..."
if [ "$USE_SSHPASS" = true ] && command -v sshpass &> /dev/null; then
    # Тест подключения с паролем
    if sshpass -p "$NODE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$NODE_USER@$NODE_IP" "echo 'SSH connection successful'" 2>&1 | grep -q "SSH connection successful"; then
        echo "   ✅ SSH подключение успешно (с паролем)"
    else
        echo "   ⚠️  Подключение с паролем не удалось, пробую SSH ключи..."
        USE_SSHPASS=false
    fi
else
    # Тест подключения с SSH ключами
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$NODE_USER@$NODE_IP" "echo 'SSH key connection successful'" 2>/dev/null | grep -q "SSH key connection successful"; then
        echo "   ✅ SSH подключение успешно (SSH ключи)"
    else
        echo "   ❌ SSH подключение не удалось"
        exit 1
    fi
fi

# 3. Копирование скрипта установки на ноду
echo ""
echo "3️⃣  Копирование скрипта установки на ноду..."
if [ "$USE_SSHPASS" = true ]; then
    if sshpass -p "$NODE_PASSWORD" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 node-auto-setup.sh "$NODE_USER@$NODE_IP:/tmp/node-auto-setup.sh" 2>&1; then
        echo "   ✅ Скрипт скопирован (с паролем)"
    else
        echo "   ❌ Ошибка копирования с паролем, пробую SSH ключи..."
        USE_SSHPASS=false
        scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 node-auto-setup.sh "$NODE_USER@$NODE_IP:/tmp/node-auto-setup.sh" || {
            echo "   ❌ Ошибка копирования скрипта"
            echo "   💡 Решения:"
            echo "      1. Проверьте пароль root на ноде"
            echo "      2. Настройте SSH ключи: ssh-copy-id $NODE_USER@$NODE_IP"
            echo "      3. Или скопируйте скрипт вручную и выполните на ноде"
            exit 1
        }
    fi
else
    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 node-auto-setup.sh "$NODE_USER@$NODE_IP:/tmp/node-auto-setup.sh" || {
        echo "   ❌ Ошибка копирования скрипта"
        echo "   💡 Решения:"
        echo "      1. Настройте SSH ключи: ssh-copy-id $NODE_USER@$NODE_IP"
        echo "      2. Или скопируйте скрипт вручную и выполните на ноде"
        exit 1
    }
fi

echo "   ✅ Скрипт скопирован"

# 4. Выполнение скрипта установки на ноде
echo ""
echo "4️⃣  Выполнение установки на ноде..."
if [ "$USE_SSHPASS" = true ]; then
    sshpass -p "$NODE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$NODE_USER@$NODE_IP" bash <<EOF
export NODE_IP="$NODE_IP"
export CONTROL_SERVER_URL="$CONTROL_SERVER_URL"
export NODE_PORT="$NODE_PORT"
export API_PORT="$API_PORT"
export CERTIFICATE='$CERTIFICATE'
chmod +x /tmp/node-auto-setup.sh
/tmp/node-auto-setup.sh
EOF
else
    ssh -o StrictHostKeyChecking=no "$NODE_USER@$NODE_IP" bash <<EOF
export NODE_IP="$NODE_IP"
export CONTROL_SERVER_URL="$CONTROL_SERVER_URL"
export NODE_PORT="$NODE_PORT"
export API_PORT="$API_PORT"
export CERTIFICATE='$CERTIFICATE'
chmod +x /tmp/node-auto-setup.sh
/tmp/node-auto-setup.sh
EOF
fi

echo "   ✅ Установка выполнена"

# 5. Синхронизация сертификата и ключа с ноды в базу данных
echo ""
echo "5️⃣  Синхронизация сертификата и ключа..."
chmod +x sync-cert-and-key-from-node.sh
./sync-cert-and-key-from-node.sh

# 6. Создание ноды в Marzban через API
echo ""
echo "6️⃣  Создание ноды в Marzban..."
# Получение токена администратора
ADMIN_TOKEN=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import urllib.request
import urllib.parse
import json
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

try:
    # Получить пароль из переменных окружения
    import os
    admin_pass = os.environ.get('ADMIN_PASS') or os.environ.get('SUDO_PASSWORD') or 'Amfetamin1234'
    
    token_req = urllib.request.Request('https://marzban:62050/api/admin/token')
    token_req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    token_data = f'username=root&password={admin_pass}'.encode()
    
    with urllib.request.urlopen(token_req, data=token_data, timeout=5, context=ssl_context) as token_resp:
        token_data = json.loads(token_resp.read().decode())
        print(token_data.get('access_token', ''))
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning" | tail -1)

if [ -z "$ADMIN_TOKEN" ] || echo "$ADMIN_TOKEN" | grep -q "ERROR"; then
    echo "   ⚠️  Не удалось получить токен, создайте ноду вручную в панели"
else
    # Создание ноды через API
    NODE_CREATE_RESPONSE=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
import urllib.request
import json
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

token = '$ADMIN_TOKEN'
node_data = {
    'name': '$NODE_NAME',
    'address': '$NODE_IP',
    'port': $NODE_PORT,
    'api_port': $API_PORT,
    'usage_coefficient': 1.0,
    'add_as_new_host': False
}

try:
    node_req = urllib.request.Request('https://marzban:62050/api/node')
    node_req.add_header('Authorization', f'Bearer {token}')
    node_req.add_header('Content-Type', 'application/json')
    
    with urllib.request.urlopen(node_req, data=json.dumps(node_data).encode(), timeout=10, context=ssl_context) as node_resp:
        response = json.loads(node_resp.read().decode())
        print(json.dumps(response, indent=2))
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")
    
    if echo "$NODE_CREATE_RESPONSE" | grep -q "ERROR"; then
        echo "   ⚠️  Не удалось создать ноду через API:"
        echo "$NODE_CREATE_RESPONSE" | sed 's/^/      /'
        echo "   💡 Создайте ноду вручную в панели:"
        echo "      https://panel.anomaly-connect.online -> Nodes -> Add Node"
    else
        echo "   ✅ Нода создана в Marzban"
        echo "$NODE_CREATE_RESPONSE" | sed 's/^/      /'
    fi
fi

echo ""
echo "✅ Автоматическая настройка завершена!"
echo ""
echo "💡 Следующие шаги:"
echo "   1. Проверьте статус ноды в панели: https://panel.anomaly-connect.online"
echo "   2. Перейдите в Nodes -> $NODE_NAME"
echo "   3. Нажмите 'Переподключиться'"
echo "   4. Проверьте статус подключения"
echo ""


#!/bin/bash

# Пересоздание ноды с правильной парой сертификат/ключ

echo "🔧 Пересоздание ноды с правильной парой сертификат/ключ"
echo "========================================================"
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"
NODE_NAME="Node 1"
NODE_PORT=62050
API_PORT=62051

echo "📋 Параметры ноды:"
echo "   IP: $NODE_IP"
echo "   Name: $NODE_NAME"
echo "   Port: $NODE_PORT"
echo "   API Port: $API_PORT"
echo ""

# 1. Получение информации о текущей ноде
echo "1️⃣  Получение информации о текущей ноде..."
NODE_INFO=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

try:
    with GetDB() as db:
        node = db.query(Node).filter(Node.address == '$NODE_IP').first()
        if node:
            print(f\"{node.id}|{node.name}\")
        else:
            print('NOT_FOUND')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)

if [[ "$NODE_INFO" == ERROR* ]]; then
    echo "❌ Ошибка при получении информации о ноде: $NODE_INFO"
    exit 1
fi

if [ "$NODE_INFO" != "NOT_FOUND" ]; then
    NODE_ID=$(echo "$NODE_INFO" | cut -d'|' -f1)
    echo "   Найдена нода ID: $NODE_ID"
    echo ""
    
    echo "2️⃣  Удаление старой ноды из базы данных..."
    docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

try:
    with GetDB() as db:
        node = db.query(Node).filter(Node.id == $NODE_ID).first()
        if node:
            db.delete(node)
            db.commit()
            print('SUCCESS: Node deleted')
        else:
            print('ERROR: Node not found')
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Нода удалена из базы данных"
    else
        echo "   ⚠️  Ошибка при удалении ноды, продолжаем..."
    fi
    echo ""
else
    echo "   ⚠️  Нода не найдена в базе данных, создаем новую"
    echo ""
fi

# 3. Создание новой ноды в базе данных
echo "3️⃣  Создание новой ноды в базе данных..."
NEW_NODE_ID=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import Node

try:
    with GetDB() as db:
        # Проверяем, нет ли уже ноды с таким IP
        existing = db.query(Node).filter(Node.address == '$NODE_IP').first()
        if existing:
            print(f\"{existing.id}\")
        else:
            new_node = Node(
                name='$NODE_NAME',
                address='$NODE_IP',
                port=$NODE_PORT,
                api_port=$API_PORT,
                usage_coefficient=1.0
            )
            db.add(new_node)
            db.commit()
            db.refresh(new_node)
            print(f\"{new_node.id}\")
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1)

if [[ "$NEW_NODE_ID" == ERROR* ]]; then
    echo "❌ Ошибка при создании ноды: $NEW_NODE_ID"
    exit 1
fi

echo "   ✅ Нода создана (ID: $NEW_NODE_ID)"
echo ""

# 4. Ожидание генерации сертификата Marzban
echo "4️⃣  Ожидание генерации сертификата Marzban..."
echo "   ⏳ Ожидание 10 секунд для генерации сертификата..."
sleep 10

# 5. Получение нового сертификата из базы данных
echo "5️⃣  Получение нового сертификата из базы данных..."
MAX_RETRIES=10
RETRY=0
NEW_CERT=""

while [ $RETRY -lt $MAX_RETRIES ]; do
    NEW_CERT=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls and tls.certificate:
            cert = tls.certificate
            if 'BEGIN CERTIFICATE' in cert:
                print(cert)
                exit(0)
            else:
                print('ERROR: Invalid certificate format', file=sys.stderr)
                exit(1)
        else:
            print('ERROR: No certificate in database', file=sys.stderr)
            exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    exit(1)
" 2>&1)
    
    if [ ! -z "$NEW_CERT" ] && [[ ! "$NEW_CERT" == ERROR* ]] && [ "$(echo "$NEW_CERT" | grep -c "BEGIN CERTIFICATE")" -gt 0 ]; then
        break
    fi
    
    RETRY=$((RETRY + 1))
    if [ $RETRY -lt $MAX_RETRIES ]; then
        echo "   ⏳ Повторная попытка ($RETRY/$MAX_RETRIES)..."
        sleep 5
    fi
done

if [ -z "$NEW_CERT" ] || [[ "$NEW_CERT" == ERROR* ]] || [ ! "$(echo "$NEW_CERT" | grep -c "BEGIN CERTIFICATE")" -gt 0 ]; then
    echo "❌ Не удалось получить новый сертификат из базы данных"
    echo "   💡 Попробуйте создать ноду вручную через панель"
    exit 1
fi

echo "✅ Новый сертификат получен ($(echo "$NEW_CERT" | wc -c) байт)"
echo ""

# 6. Получение ключа из базы данных
echo "6️⃣  Получение ключа из базы данных..."
NEW_KEY=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls and tls.key:
            print(tls.key)
        else:
            print('ERROR: No key in database', file=sys.stderr)
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [[ "$NEW_KEY" == ERROR* ]] || [ -z "$NEW_KEY" ]; then
    echo "❌ Не удалось получить ключ из базы данных"
    exit 1
fi

echo "✅ Ключ получен ($(echo "$NEW_KEY" | wc -c) байт)"
echo ""

# 7. Проверка соответствия нового сертификата и ключа
echo "7️⃣  Проверка соответствия нового сертификата и ключа..."
CERT_KEY_MATCH=$(docker exec anomaly-marzban python3 -c "
import sys
import tempfile
import subprocess

cert = '''$NEW_CERT'''
key = '''$NEW_KEY'''

# Создаем временные файлы
with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as cert_file:
    cert_file.write(cert)
    cert_path = cert_file.name

with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as key_file:
    key_file.write(key)
    key_path = key_file.name

try:
    # Получаем modulus сертификата
    cert_mod = subprocess.check_output(['openssl', 'x509', '-noout', '-modulus', '-in', cert_path], stderr=subprocess.DEVNULL).decode().strip()
    
    # Получаем modulus ключа
    key_mod = subprocess.check_output(['openssl', 'rsa', '-noout', '-modulus', '-in', key_path], stderr=subprocess.DEVNULL).decode().strip()
    
    if cert_mod == key_mod:
        print('MATCH')
    else:
        print('MISMATCH')
except Exception as e:
    print(f'ERROR: {e}')
finally:
    import os
    os.unlink(cert_path)
    os.unlink(key_path)
" 2>&1)

if [ "$CERT_KEY_MATCH" = "MATCH" ]; then
    echo "   ✅ Новый сертификат и ключ совпадают!"
else
    echo "   ❌ Новый сертификат и ключ все еще не совпадают"
    echo "   💡 Возможно, нужно создать ноду через панель вручную"
    exit 1
fi

echo ""

# 8. Установка сертификата на ноду
echo "8️⃣  Установка сертификата на ноду..."
echo "$NEW_CERT" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'cat > /var/lib/marzban-node/ssl/certificate.pem'" 2>&1 | grep -v "password:"

if [ $? -eq 0 ]; then
    echo "✅ Сертификат установлен на ноде"
else
    echo "❌ Ошибка при установке сертификата на ноду"
    exit 1
fi

echo ""

# 9. Установка ключа на ноду
echo "9️⃣  Установка ключа на ноду..."
echo "$NEW_KEY" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'mkdir -p /var/lib/marzban-node/node-certs && cat > /var/lib/marzban-node/node-certs/key.pem'" 2>&1 | grep -v "password:"

if [ $? -eq 0 ]; then
    echo "✅ Ключ установлен на ноде"
else
    echo "❌ Ошибка при установке ключа на ноду"
    exit 1
fi

echo ""

# 10. Перезапуск ноды
echo "🔟 Перезапуск ноды..."
ssh root@$NODE_IP "cd /opt/Anomaly && docker-compose -f docker-compose.node.yml restart anomaly-node" 2>&1 | grep -v "password:"
sleep 10

echo ""

# 11. Перезапуск Marzban
echo "1️⃣1️⃣  Перезапуск Marzban..."
docker-compose restart marzban
sleep 10

echo ""

# 12. Финальная проверка
echo "1️⃣2️⃣  Финальная проверка соответствия на ноде..."
FINAL_MATCH=$(ssh root@$NODE_IP "docker exec anomaly-node sh -c '
CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem
KEY_FILE=/var/lib/marzban-node/node-certs/key.pem

if [ -f \"\$CERT_FILE\" ] && [ -f \"\$KEY_FILE\" ]; then
    CERT_MOD=\$(openssl x509 -noout -modulus -in \"\$CERT_FILE\" 2>/dev/null)
    KEY_MOD=\$(openssl rsa -noout -modulus -in \"\$KEY_FILE\" 2>/dev/null)
    
    if [ \"\$CERT_MOD\" = \"\$KEY_MOD\" ]; then
        echo \"MATCH\"
    else
        echo \"MISMATCH\"
    fi
else
    echo \"NOT_FOUND\"
fi
'" 2>&1 | grep -v "password:" | tail -1)

if [ "$FINAL_MATCH" = "MATCH" ]; then
    echo "   ✅ Сертификат и ключ на ноде совпадают!"
    echo ""
    echo "✅ Пересоздание ноды завершено успешно!"
    echo ""
    echo "💡 Следующие шаги:"
    echo "   1. Подождите 30-60 секунд"
    echo "   2. Откройте панель: https://panel.anomaly-connect.online"
    echo "   3. Перейдите в Nodes → Node 1"
    echo "   4. Нажмите 'Переподключиться'"
    echo "   5. Проверьте статус ноды"
else
    echo "   ❌ Сертификат и ключ все еще не совпадают"
    echo ""
    echo "💡 Попробуйте создать ноду вручную через панель:"
    echo "   1. Удалите ноду в панели"
    echo "   2. Создайте ноду заново"
    echo "   3. Скачайте сертификат"
    echo "   4. Выполните: ./fix-node-cert-direct.sh"
fi


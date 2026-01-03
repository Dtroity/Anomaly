#!/bin/bash

# Прямое исправление проблемы KEY_VALUES_MISMATCH
# Работает напрямую с базой данных и файлами, минуя API

echo "🔧 Прямое исправление KEY_VALUES_MISMATCH"
echo "=========================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"

echo "📋 Проблема: Сертификат на ноде не соответствует ключу в базе данных"
echo "   Решение: Установить сертификат из базы данных на ноду"
echo ""

# 1. Получение сертификата из базы данных
echo "1️⃣  Получение сертификата из базы данных Marzban..."
DB_CERT=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls and tls.certificate:
            print(tls.certificate)
        else:
            print('ERROR: No certificate in database', file=sys.stderr)
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources")

if [[ "$DB_CERT" == ERROR* ]] || [ -z "$DB_CERT" ] || [ ! "$(echo "$DB_CERT" | grep -c "BEGIN CERTIFICATE")" -gt 0 ]; then
    echo "❌ Не удалось получить сертификат из базы данных"
    echo "   Ошибка: $DB_CERT"
    exit 1
fi

echo "✅ Сертификат получен из базы данных ($(echo "$DB_CERT" | wc -c) байт)"
echo ""

# 2. Получение ключа из базы данных
echo "2️⃣  Получение ключа из базы данных Marzban..."
DB_KEY=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
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
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources")

if [[ "$DB_KEY" == ERROR* ]] || [ -z "$DB_KEY" ] || [ ! "$(echo "$DB_KEY" | grep -c "BEGIN.*PRIVATE KEY")" -gt 0 ]; then
    echo "❌ Не удалось получить ключ из базы данных"
    echo "   Ошибка: $DB_KEY"
    exit 1
fi

echo "✅ Ключ получен из базы данных ($(echo "$DB_KEY" | wc -c) байт)"
echo ""

# 3. Проверка соответствия сертификата и ключа из базы данных
echo "3️⃣  Проверка соответствия сертификата и ключа из базы данных..."
CERT_KEY_MATCH=$(docker exec anomaly-marzban python3 -c "
import sys
import tempfile
import subprocess

cert = '''$DB_CERT'''
key = '''$DB_KEY'''

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
    echo "   ✅ Сертификат и ключ в базе данных совпадают"
else
    echo "   ❌ Сертификат и ключ в базе данных НЕ совпадают"
    echo "   💡 Нужно пересоздать ноду в панели для получения правильной пары"
    exit 1
fi

echo ""

# 4. Установка сертификата на ноду
echo "4️⃣  Установка сертификата на ноду..."
echo "$DB_CERT" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'cat > /var/lib/marzban-node/ssl/certificate.pem'" 2>&1 | grep -v "password:"

if [ $? -eq 0 ]; then
    echo "✅ Сертификат установлен на ноде"
else
    echo "❌ Ошибка при установке сертификата на ноду"
    exit 1
fi

echo ""

# 5. Установка ключа на ноду (если нужно)
echo "5️⃣  Проверка ключа на ноде..."
NODE_KEY_EXISTS=$(ssh root@$NODE_IP "docker exec anomaly-node test -f /var/lib/marzban-node/node-certs/key.pem && echo 'yes' || echo 'no'" 2>&1 | grep -v "password:" | tail -1)

if [ "$NODE_KEY_EXISTS" = "yes" ]; then
    echo "   ✅ Ключ уже существует на ноде"
    echo "   Проверка соответствия..."
    
    CERT_KEY_MATCH_NODE=$(ssh root@$NODE_IP "docker exec anomaly-node sh -c '
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
    
    if [ "$CERT_KEY_MATCH_NODE" = "MATCH" ]; then
        echo "   ✅ Сертификат и ключ на ноде теперь совпадают!"
    else
        echo "   ⚠️  Ключ на ноде не соответствует сертификату"
        echo "   Установка ключа из базы данных..."
        echo "$DB_KEY" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'cat > /var/lib/marzban-node/node-certs/key.pem'" 2>&1 | grep -v "password:"
        
        if [ $? -eq 0 ]; then
            echo "   ✅ Ключ установлен на ноде"
        else
            echo "   ❌ Ошибка при установке ключа"
        fi
    fi
else
    echo "   ⚠️  Ключ не найден на ноде, устанавливаю..."
    echo "$DB_KEY" | ssh root@$NODE_IP "docker exec -i anomaly-node sh -c 'mkdir -p /var/lib/marzban-node/node-certs && cat > /var/lib/marzban-node/node-certs/key.pem'" 2>&1 | grep -v "password:"
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Ключ установлен на ноде"
    else
        echo "   ❌ Ошибка при установке ключа"
    fi
fi

echo ""

# 6. Перезапуск ноды
echo "6️⃣  Перезапуск ноды..."
ssh root@$NODE_IP "cd /opt/Anomaly && docker-compose -f docker-compose.node.yml restart anomaly-node" 2>&1 | grep -v "password:"
sleep 10

echo ""

# 7. Финальная проверка
echo "7️⃣  Финальная проверка соответствия..."
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
    echo "✅ Исправление завершено!"
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
    echo "💡 Возможно, нужно пересоздать ноду в панели для получения новой пары сертификат/ключ"
fi


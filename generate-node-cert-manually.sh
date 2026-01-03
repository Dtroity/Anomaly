#!/bin/bash

# Ручная генерация сертификата для ноды, если Marzban не генерирует его автоматически

echo "🔐 Ручная генерация сертификата для ноды"
echo "========================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

echo "1️⃣  Проверка наличия сертификата в базе данных..."
CERT_EXISTS=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls and tls.certificate and tls.key:
            print('EXISTS')
        else:
            print('NOT_FOUND')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources" | tail -1)

if [ "$CERT_EXISTS" = "EXISTS" ]; then
    echo "   ✅ Сертификат уже существует в базе данных"
    echo ""
    echo "2️⃣  Проверка соответствия сертификата и ключа..."
    ./fix-node-cert-direct.sh
    exit $?
fi

echo "   ❌ Сертификат не найден в базе данных"
echo ""

echo "2️⃣  Генерация нового сертификата..."
NEW_CERT_PAIR=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.utils.crypto import generate_certificate
from app.db import GetDB
from app.db.models import TLS

try:
    # Генерируем новую пару сертификат/ключ
    tls_data = generate_certificate()
    cert = tls_data['cert']
    key = tls_data['key']
    
    # Сохраняем в базу данных
    with GetDB() as db:
        # Удаляем старые записи
        db.query(TLS).delete()
        
        # Создаем новую запись
        new_tls = TLS(
            id=1,
            certificate=cert,
            key=key
        )
        db.add(new_tls)
        db.commit()
        
        print('SUCCESS')
        print(f'CERT_LEN: {len(cert)}')
        print(f'KEY_LEN: {len(key)}')
except Exception as e:
    print(f'ERROR: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources")

if [[ "$NEW_CERT_PAIR" == ERROR* ]]; then
    echo "❌ Ошибка при генерации сертификата: $NEW_CERT_PAIR"
    exit 1
fi

if echo "$NEW_CERT_PAIR" | grep -q "SUCCESS"; then
    CERT_LEN=$(echo "$NEW_CERT_PAIR" | grep "CERT_LEN" | cut -d':' -f2 | tr -d ' ')
    KEY_LEN=$(echo "$NEW_CERT_PAIR" | grep "KEY_LEN" | cut -d':' -f2 | tr -d ' ')
    echo "   ✅ Новый сертификат сгенерирован и сохранен в базу данных"
    echo "      Сертификат: $CERT_LEN байт"
    echo "      Ключ: $KEY_LEN байт"
    echo ""
    
    echo "3️⃣  Проверка соответствия нового сертификата и ключа..."
    sleep 2
    
    MATCH_CHECK=$(docker exec anomaly-marzban python3 -c "
import sys
import warnings
import tempfile
import subprocess
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls and tls.certificate and tls.key:
            cert = tls.certificate
            key = tls.key
            
            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as cert_file:
                cert_file.write(cert)
                cert_path = cert_file.name
            
            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as key_file:
                key_file.write(key)
                key_path = key_file.name
            
            try:
                cert_mod = subprocess.check_output(['openssl', 'x509', '-noout', '-modulus', '-in', cert_path], stderr=subprocess.DEVNULL).decode().strip()
                key_mod = subprocess.check_output(['openssl', 'rsa', '-noout', '-modulus', '-in', key_path], stderr=subprocess.DEVNULL).decode().strip()
                
                if cert_mod == key_mod:
                    print('MATCH')
                else:
                    print('MISMATCH')
            except:
                print('ERROR')
            finally:
                import os
                os.unlink(cert_path)
                os.unlink(key_path)
        else:
            print('NOT_FOUND')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources" | tail -1)
    
    if [ "$MATCH_CHECK" = "MATCH" ]; then
        echo "   ✅ Сертификат и ключ совпадают!"
        echo ""
        echo "4️⃣  Установка сертификата на ноду..."
        ./fix-node-cert-direct.sh
    else
        echo "   ❌ Сертификат и ключ не совпадают: $MATCH_CHECK"
        echo "   💡 Это неожиданно, так как они были сгенерированы вместе"
        exit 1
    fi
else
    echo "❌ Не удалось сгенерировать сертификат"
    exit 1
fi


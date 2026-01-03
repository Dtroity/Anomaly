#!/bin/bash

# Полное решение проблемы KEY_VALUES_MISMATCH
# Удаляет старый сертификат из БД, создает ноду через панель, устанавливает правильный сертификат

echo "🔧 Полное решение проблемы KEY_VALUES_MISMATCH"
echo "=============================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

NODE_IP="185.126.67.67"

echo "📋 Проблема: Сертификат и ключ в базе данных не совпадают"
echo "   Это происходит даже после пересоздания ноды"
echo ""

# 1. Проверка текущего состояния
echo "1️⃣  Проверка текущего состояния..."
CURRENT_MATCH=$(docker exec anomaly-marzban python3 -c "
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
            
            # Создаем временные файлы
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

if [ "$CURRENT_MATCH" = "MATCH" ]; then
    echo "   ✅ Сертификат и ключ в базе данных совпадают"
    echo ""
    echo "2️⃣  Установка сертификата на ноду..."
    ./fix-node-cert-direct.sh
    exit $?
elif [ "$CURRENT_MATCH" = "MISMATCH" ]; then
    echo "   ❌ Сертификат и ключ в базе данных НЕ совпадают"
    echo ""
    
    echo "2️⃣  Удаление неправильного сертификата из базы данных..."
    docker exec anomaly-marzban python3 -c "
import sys
import warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls_records = db.query(TLS).all()
        for tls in tls_records:
            db.delete(tls)
        db.commit()
        print('SUCCESS: TLS records deleted')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning" | grep -v "pkg_resources"
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Старые сертификаты удалены из базы данных"
    else
        echo "   ⚠️  Ошибка при удалении, продолжаем..."
    fi
    echo ""
    
    echo "3️⃣  Перезапуск Marzban для очистки кэша..."
    docker-compose restart marzban
    sleep 10
    echo ""
    
    echo "4️⃣  Инструкция для создания ноды:"
    echo "   📋 ВАЖНО: Создайте ноду через панель, чтобы Marzban сгенерировал правильную пару"
    echo ""
    echo "   Шаги:"
    echo "   1. Откройте: https://panel.anomaly-connect.online"
    echo "   2. Перейдите в Nodes"
    echo "   3. Убедитесь, что нода 'Node 1' удалена (если есть)"
    echo "   4. Создайте новую ноду:"
    echo "      - Имя: Node 1"
    echo "      - Адрес: $NODE_IP"
    echo "      - Порт: 62050"
    echo "      - API порт: 62051"
    echo "   5. После создания подождите 15-20 секунд"
    echo ""
    read -p "   Нажмите Enter после создания ноды в панели..."
    echo ""
    
    echo "5️⃣  Проверка нового сертификата..."
    sleep 5
    
    NEW_MATCH=$(docker exec anomaly-marzban python3 -c "
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
    
    if [ "$NEW_MATCH" = "MATCH" ]; then
        echo "   ✅ Новый сертификат и ключ совпадают!"
        echo ""
        echo "6️⃣  Установка сертификата на ноду..."
        ./fix-node-cert-direct.sh
    elif [ "$NEW_MATCH" = "NOT_FOUND" ]; then
        echo "   ❌ Сертификат не найден в базе данных"
        echo "   💡 Убедитесь, что нода создана в панели и подождите еще 10 секунд"
        echo "   Затем выполните: ./fix-node-cert-direct.sh"
    else
        echo "   ❌ Новый сертификат и ключ все еще не совпадают"
        echo "   💡 Это указывает на проблему в Marzban"
        echo "   Попробуйте перезапустить Marzban: docker-compose restart marzban"
        echo "   Затем создайте ноду заново"
    fi
else
    echo "   ❌ Ошибка при проверке: $CURRENT_MATCH"
    echo "   💡 Попробуйте создать ноду в панели и выполнить: ./fix-node-cert-direct.sh"
fi


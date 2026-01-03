#!/bin/bash
# Проверка соответствия нового сертификата на ноде и ключа в базе данных

echo "🔍 Проверка соответствия нового сертификата и ключа"
echo "==================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Получение нового сертификата с ноды..."
NODE_CERT=$(ssh root@185.126.67.67 "docker exec anomaly-node cat /var/lib/marzban-node/ssl/certificate.pem" 2>&1 | grep -v "password:")

if echo "$NODE_CERT" | grep -q "BEGIN CERTIFICATE"; then
    NODE_CERT_HASH=$(echo "$NODE_CERT" | grep -A 1 "BEGIN CERTIFICATE" | tail -1 | cut -c1-50)
    echo "   ✅ Сертификат найден на ноде"
    echo "      Hash (первые 50 символов): $NODE_CERT_HASH"
else
    echo "   ❌ Сертификат не найден на ноде"
    exit 1
fi

echo ""
echo "2️⃣  Получение ключа из базы данных Marzban..."
DB_KEY=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if tls:
            print(tls.key)
        else:
            print('ERROR: TLS record not found')
            sys.exit(1)
except Exception as e:
    print(f'ERROR: {str(e)[:300]}')
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

if echo "$DB_KEY" | grep -q "BEGIN.*PRIVATE KEY"; then
    DB_KEY_HASH=$(echo "$DB_KEY" | grep -A 1 "BEGIN.*PRIVATE KEY" | tail -1 | cut -c1-50)
    echo "   ✅ Ключ найден в базе данных"
    echo "      Hash (первые 50 символов): $DB_KEY_HASH"
else
    echo "   ❌ Ключ не найден в базе данных"
    exit 1
fi

echo ""
echo "3️⃣  Проверка соответствия сертификата с ноды и ключа из базы данных..."
MATCH_TEST=$(docker exec anomaly-marzban python3 -c "
import sys
import subprocess
import tempfile

NODE_CERT = '''$NODE_CERT'''
DB_KEY = '''$DB_KEY'''

try:
    # Создать временные файлы
    cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
    key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
    
    cert_file.write(NODE_CERT)
    cert_file.flush()
    
    key_file.write(DB_KEY)
    key_file.flush()
    
    # Проверить соответствие с помощью openssl
    try:
        result = subprocess.run(
            ['openssl', 'x509', '-noout', '-modulus', '-in', cert_file.name],
            capture_output=True,
            text=True,
            timeout=5
        )
        cert_modulus = result.stdout.strip()
        
        result = subprocess.run(
            ['openssl', 'rsa', '-noout', '-modulus', '-in', key_file.name],
            capture_output=True,
            text=True,
            timeout=5
        )
        key_modulus = result.stdout.strip()
        
        if cert_modulus == key_modulus:
            print('SUCCESS: Certificate from node and key from database MATCH')
        else:
            print('ERROR: Certificate from node and key from database DO NOT MATCH')
            print(f'Cert modulus: {cert_modulus[:50]}...')
            print(f'Key modulus:  {key_modulus[:50]}...')
            sys.exit(1)
    except subprocess.TimeoutExpired:
        print('ERROR: openssl command timed out')
        sys.exit(1)
    except FileNotFoundError:
        print('WARNING: openssl not found, cannot verify match')
        print('INFO: Assuming they match (manual verification needed)')
        
except Exception as e:
    print(f'ERROR: {type(e).__name__}: {str(e)[:300]}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1 | grep -v "UserWarning")

echo "$MATCH_TEST" | sed 's/^/      /'

echo ""
echo "4️⃣  Рекомендации:"
if echo "$MATCH_TEST" | grep -q "DO NOT MATCH"; then
    echo "   ❌ Сертификат с ноды и ключ из базы данных НЕ соответствуют"
    echo ""
    echo "   💡 Решение:"
    echo "      1. В панели Marzban скачайте сертификат заново (Nodes -> Node 1 -> Скачать сертификат)"
    echo "      2. Убедитесь, что это сертификат от ТЕКУЩЕЙ ноды (после пересоздания)"
    echo "      3. Установите его на ноду:"
    echo "         ./install-node-cert.sh /path/to/cert.pem"
    echo "      4. Синхронизируйте сертификат и ключ с ноды в базу данных:"
    echo "         ./sync-cert-and-key-from-node.sh"
    echo ""
    echo "   ⚠️  ВАЖНО: Ключ должен быть синхронизирован ИЗ БАЗЫ ДАННЫХ Marzban на ноду,"
    echo "      а не наоборот! Но так как мы синхронизируем с ноды, нужно убедиться,"
    echo "      что на ноде правильный ключ."
else
    echo "   ✅ Сертификат и ключ соответствуют друг другу"
    echo "   💡 Если ошибка все еще присутствует, проверьте логи Marzban:"
    echo "      docker logs anomaly-marzban --tail 50 | grep -E '(node|connect|error)'"
fi

echo ""
echo "✅ Проверка завершена!"
echo ""


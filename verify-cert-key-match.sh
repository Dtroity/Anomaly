#!/bin/bash
# Проверка соответствия сертификата и ключа

echo "🔍 Проверка соответствия сертификата и ключа"
echo "============================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "1️⃣  Проверка соответствия сертификата и ключа в базе данных..."
DB_MATCH=$(docker exec anomaly-marzban python3 -c "
import sys
sys.path.insert(0, '/code')
from app.db import GetDB
from app.db.models import TLS
import subprocess
import tempfile

try:
    with GetDB() as db:
        tls = db.query(TLS).first()
        if not tls:
            print('ERROR: TLS record not found')
            sys.exit(1)
        
        cert_content = tls.certificate
        key_content = tls.key
        
        # Создать временные файлы
        cert_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        key_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem')
        
        cert_file.write(cert_content)
        cert_file.flush()
        
        key_file.write(key_content)
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
                print('SUCCESS: Certificate and key MATCH in database')
            else:
                print('ERROR: Certificate and key DO NOT MATCH in database')
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

echo "$DB_MATCH" | sed 's/^/      /'

echo ""
echo "2️⃣  Проверка соответствия сертификата и ключа на ноде..."
NODE_MATCH=$(ssh root@185.126.67.67 "docker exec anomaly-node sh -c '
CERT_FILE=/var/lib/marzban-node/ssl/certificate.pem
KEY_FILE=/var/lib/marzban-node/node-certs/key.pem

if [ -f \"\$CERT_FILE\" ] && [ -f \"\$KEY_FILE\" ]; then
    CERT_MOD=\$(openssl x509 -noout -modulus -in \"\$CERT_FILE\" 2>/dev/null)
    KEY_MOD=\$(openssl rsa -noout -modulus -in \"\$KEY_FILE\" 2>/dev/null)
    
    if [ \"\$CERT_MOD\" = \"\$KEY_MOD\" ]; then
        echo \"SUCCESS: Certificate and key MATCH on node\"
    else
        echo \"ERROR: Certificate and key DO NOT MATCH on node\"
        echo \"Cert modulus: \${CERT_MOD:0:50}...\"
        echo \"Key modulus:  \${KEY_MOD:0:50}...\"
    fi
else
    echo \"ERROR: Certificate or key file not found\"
fi
'" 2>&1 | grep -v "password:")

echo "$NODE_MATCH" | sed 's/^/      /'

echo ""
echo "3️⃣  Рекомендации:"
echo "   💡 Если сертификат и ключ не соответствуют друг другу:"
echo "      1. Удалите ноду в панели Marzban"
echo "      2. Создайте ноду заново"
echo "      3. Скачайте новый сертификат из панели"
echo "      4. Установите сертификат на ноду:"
echo "         ./install-node-cert.sh /path/to/new-cert.pem"
echo "      5. Синхронизируйте сертификат и ключ с ноды в базу данных:"
echo "         ./sync-cert-and-key-from-node.sh"
echo ""

echo "✅ Проверка завершена!"
echo ""


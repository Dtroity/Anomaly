#!/bin/bash

# Скрипт для получения приватного ключа ноды из панели Marzban через API

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔑 Получение приватного ключа ноды"
echo "==================================="
echo ""

# 1. Проверить наличие .env.node
if [ ! -f .env.node ]; then
    echo "❌ .env.node не найден"
    exit 1
fi

# 2. Получить данные из .env.node
CONTROL_SERVER=$(grep "^CONTROL_SERVER=" .env.node | cut -d'=' -f2 | tr -d '"' | tr -d "'")
NODE_ID=$(grep "^NODE_ID=" .env.node | cut -d'=' -f2 | tr -d '"' | tr -d "'")

if [ -z "$CONTROL_SERVER" ]; then
    echo "❌ CONTROL_SERVER не найден в .env.node"
    exit 1
fi

if [ -z "$NODE_ID" ]; then
    echo "❌ NODE_ID не найден в .env.node"
    exit 1
fi

echo "📋 Параметры ноды:"
echo "  Control Server: $CONTROL_SERVER"
echo "  Node ID: $NODE_ID"
echo ""

# 3. Инструкции для ручного получения
echo "💡 Инструкция по получению ключа:"
echo ""
echo "   Способ 1 (через панель):"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online/dashboard/"
echo "   2. Войдите в систему"
echo "   3. Перейдите в раздел 'Nodes' (Ноды)"
echo "   4. Найдите вашу ноду (ID: $NODE_ID)"
echo "   5. Нажмите на ноду, чтобы открыть детали"
echo "   6. Найдите кнопку 'Download Certificate' или 'Скачать сертификат'"
echo "   7. Скачайте файл (обычно это один .pem файл, содержащий и сертификат, и ключ)"
echo "   8. Скопируйте файл на ноду (например, через scp):"
echo "      scp downloaded-cert.pem root@$(hostname -I | awk '{print $1}'):/opt/Anomaly/node-certs/"
echo "   9. Запустите: ./extract-node-cert-and-key.sh"
echo ""
echo "   Способ 2 (через API - если настроен):"
echo "   1. Получите токен API из панели Marzban (Settings -> API)"
echo "   2. Выполните запрос к API для получения сертификата ноды"
echo ""
read -p "Нажмите Enter после того, как скачаете сертификат из панели..." -r
echo ""

# 4. Проверить, есть ли новый файл
echo "📋 Поиск скачанных файлов..."
FOUND_FILES=$(find node-certs/ -name "*.pem" -o -name "*.crt" -o -name "*.key" 2>/dev/null | grep -v "certificate.pem" | grep -v "key.pem" | head -n 1)

if [ -n "$FOUND_FILES" ]; then
    echo "  Найден файл: $FOUND_FILES"
    read -p "Использовать этот файл? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SOURCE_FILE="$FOUND_FILES"
    else
        read -p "Введите путь к скачанному файлу: " SOURCE_FILE
    fi
else
    read -p "Введите путь к скачанному файлу из панели: " SOURCE_FILE
fi

if [ -z "$SOURCE_FILE" ] || [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Файл не найден: $SOURCE_FILE"
    exit 1
fi

echo ""
echo "📋 Анализ файла: $SOURCE_FILE"
FILE_CONTENT=$(cat "$SOURCE_FILE")

# Проверить, содержит ли файл и сертификат, и ключ
if echo "$FILE_CONTENT" | grep -q "BEGIN CERTIFICATE" && echo "$FILE_CONTENT" | grep -q "BEGIN.*PRIVATE KEY"; then
    echo "  ✅ Файл содержит и сертификат, и ключ"
    
    # Создать резервные копии
    mkdir -p node-certs
    [ -f node-certs/certificate.pem ] && cp node-certs/certificate.pem node-certs/certificate.pem.backup
    [ -f node-certs/key.pem ] && cp node-certs/key.pem node-certs/key.pem.backup
    
    # Извлечь сертификат
    echo "  Извлечение сертификата..."
    echo "$FILE_CONTENT" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > node-certs/certificate.pem
    echo "  ✅ Сертификат сохранен в node-certs/certificate.pem"
    
    # Извлечь ключ
    echo "  Извлечение приватного ключа..."
    if echo "$FILE_CONTENT" | grep -q "BEGIN RSA PRIVATE KEY"; then
        echo "$FILE_CONTENT" | sed -n '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/p' > node-certs/key.pem
        echo "  ✅ RSA ключ извлечен"
    elif echo "$FILE_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
        echo "$FILE_CONTENT" | sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' > node-certs/key.pem
        echo "  ✅ PKCS#8 ключ извлечен"
    elif echo "$FILE_CONTENT" | grep -q "BEGIN EC PRIVATE KEY"; then
        echo "$FILE_CONTENT" | sed -n '/-----BEGIN EC PRIVATE KEY-----/,/-----END EC PRIVATE KEY-----/p' > node-certs/key.pem
        echo "  ✅ EC ключ извлечен"
    else
        echo "  ❌ Не удалось найти приватный ключ в файле"
        exit 1
    fi
    
    # Установить права
    chmod 644 node-certs/certificate.pem
    chmod 600 node-certs/key.pem
    echo "  ✅ Права установлены"
    echo ""
    
    # Проверить результат
    echo "📋 Проверка результата:"
    if head -n 1 node-certs/certificate.pem | grep -q "BEGIN CERTIFICATE"; then
        echo "  ✅ certificate.pem правильный"
    else
        echo "  ❌ certificate.pem неправильный"
    fi
    
    if head -n 1 node-certs/key.pem | grep -q "BEGIN.*PRIVATE KEY"; then
        echo "  ✅ key.pem правильный"
        echo ""
        echo "✅ Готово! Теперь запустите:"
        echo "   ./fix-node-ssl-mount.sh"
    else
        echo "  ❌ key.pem неправильный"
        exit 1
    fi
else
    echo "  ❌ Файл не содержит оба компонента (сертификат и ключ)"
    echo ""
    echo "💡 Возможные причины:"
    echo "   1. Файл содержит только сертификат (нужно скачать полный файл)"
    echo "   2. Файл в другом формате"
    echo ""
    echo "📋 Первые 5 строк файла:"
    head -n 5 "$SOURCE_FILE"
    echo ""
    echo "💡 Убедитесь, что вы скачали полный файл сертификата из панели Marzban,"
    echo "   который содержит и сертификат, и приватный ключ."
    exit 1
fi


#!/bin/bash

# Скрипт для извлечения сертификата и ключа из файла, скачанного из Marzban

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Извлечение сертификата и ключа"
echo "=================================="
echo ""

# 1. Проверить, есть ли объединенный файл
echo "📋 Поиск файлов сертификатов..."
if [ -f node-certs/certificate.pem ] && [ -f node-certs/key.pem ]; then
    echo "  Найдены оба файла"
    
    # Проверить, что в key.pem на самом деле
    if head -n 1 node-certs/key.pem | grep -q "BEGIN CERTIFICATE"; then
        echo "  ⚠️  key.pem содержит сертификат, а не ключ!"
        echo ""
        echo "💡 Решение:"
        echo "   1. В панели Marzban при скачивании сертификата ноды обычно скачивается один файл"
        echo "   2. Этот файл содержит и сертификат, и ключ"
        echo "   3. Нужно разделить их"
        echo ""
        read -p "Есть ли у вас исходный файл, скачанный из панели? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Введите путь к исходному файлу (или нажмите Enter для пропуска): " ORIGINAL_FILE
            if [ -n "$ORIGINAL_FILE" ] && [ -f "$ORIGINAL_FILE" ]; then
                echo "  Используем файл: $ORIGINAL_FILE"
                SOURCE_FILE="$ORIGINAL_FILE"
            else
                echo "  Файл не найден, попробуем извлечь из существующих файлов"
                SOURCE_FILE=""
            fi
        else
            SOURCE_FILE=""
        fi
    else
        echo "  ✅ key.pem выглядит правильно"
        exit 0
    fi
else
    echo "  Файлы не найдены"
    read -p "Введите путь к файлу, скачанному из панели Marzban: " SOURCE_FILE
    if [ -z "$SOURCE_FILE" ] || [ ! -f "$SOURCE_FILE" ]; then
        echo "❌ Файл не найден"
        exit 1
    fi
fi
echo ""

# 2. Создать директорию
mkdir -p node-certs

# 3. Если есть исходный файл, использовать его
if [ -n "$SOURCE_FILE" ] && [ -f "$SOURCE_FILE" ]; then
    echo "📋 Анализ исходного файла: $SOURCE_FILE"
    FILE_CONTENT=$(cat "$SOURCE_FILE")
    
    # Проверить, содержит ли файл и сертификат, и ключ
    if echo "$FILE_CONTENT" | grep -q "BEGIN CERTIFICATE" && echo "$FILE_CONTENT" | grep -q "BEGIN.*PRIVATE KEY"; then
        echo "  ✅ Файл содержит и сертификат, и ключ"
        
        # Извлечь сертификат
        echo "  Извлечение сертификата..."
        echo "$FILE_CONTENT" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > node-certs/certificate.pem
        echo "  ✅ Сертификат сохранен в node-certs/certificate.pem"
        
        # Извлечь ключ
        echo "  Извлечение приватного ключа..."
        if echo "$FILE_CONTENT" | grep -q "BEGIN RSA PRIVATE KEY"; then
            echo "$FILE_CONTENT" | sed -n '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/p' > node-certs/key.pem
        elif echo "$FILE_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
            echo "$FILE_CONTENT" | sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' > node-certs/key.pem
        elif echo "$FILE_CONTENT" | grep -q "BEGIN EC PRIVATE KEY"; then
            echo "$FILE_CONTENT" | sed -n '/-----BEGIN EC PRIVATE KEY-----/,/-----END EC PRIVATE KEY-----/p' > node-certs/key.pem
        else
            echo "  ❌ Не удалось найти приватный ключ в файле"
            exit 1
        fi
        echo "  ✅ Ключ сохранен в node-certs/key.pem"
    else
        echo "  ⚠️  Файл не содержит оба компонента"
        echo "  Попробуем использовать его как сертификат..."
        cp "$SOURCE_FILE" node-certs/certificate.pem
        echo "  ⚠️  Ключ нужно получить отдельно"
    fi
else
    # 4. Попробовать извлечь из существующих файлов
    echo "📋 Попытка извлечения из существующих файлов..."
    
    # Проверить certificate.pem
    if [ -f node-certs/certificate.pem ]; then
        CERT_CONTENT=$(cat node-certs/certificate.pem)
        
        # Если certificate.pem содержит и сертификат, и ключ
        if echo "$CERT_CONTENT" | grep -q "BEGIN.*PRIVATE KEY"; then
            echo "  ✅ certificate.pem содержит и сертификат, и ключ"
            
            # Извлечь сертификат
            echo "$CERT_CONTENT" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > node-certs/certificate.pem.tmp
            mv node-certs/certificate.pem.tmp node-certs/certificate.pem
            
            # Извлечь ключ
            if echo "$CERT_CONTENT" | grep -q "BEGIN RSA PRIVATE KEY"; then
                echo "$CERT_CONTENT" | sed -n '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/p' > node-certs/key.pem
            elif echo "$CERT_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
                echo "$CERT_CONTENT" | sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' > node-certs/key.pem
            fi
            echo "  ✅ Файлы разделены"
        else
            echo "  ⚠️  certificate.pem содержит только сертификат"
        fi
    fi
    
    # Проверить key.pem - может быть там объединенный файл
    if [ -f node-certs/key.pem ]; then
        KEY_CONTENT=$(cat node-certs/key.pem)
        
        # Если key.pem содержит и сертификат, и ключ
        if echo "$KEY_CONTENT" | grep -q "BEGIN CERTIFICATE" && echo "$KEY_CONTENT" | grep -q "BEGIN.*PRIVATE KEY"; then
            echo "  ✅ key.pem содержит и сертификат, и ключ"
            
            # Извлечь сертификат (если еще не извлечен)
            if [ ! -f node-certs/certificate.pem ] || ! head -n 1 node-certs/certificate.pem | grep -q "BEGIN CERTIFICATE"; then
                echo "$KEY_CONTENT" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > node-certs/certificate.pem
                echo "  ✅ Сертификат извлечен из key.pem"
            fi
            
            # Извлечь ключ
            if echo "$KEY_CONTENT" | grep -q "BEGIN RSA PRIVATE KEY"; then
                echo "$KEY_CONTENT" | sed -n '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/p' > node-certs/key.pem.tmp
                mv node-certs/key.pem.tmp node-certs/key.pem
            elif echo "$KEY_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
                echo "$KEY_CONTENT" | sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' > node-certs/key.pem.tmp
                mv node-certs/key.pem.tmp node-certs/key.pem
            fi
            echo "  ✅ Ключ извлечен из key.pem"
        fi
    fi
fi
echo ""

# 5. Проверить результат
echo "📋 Проверка результата:"
if [ -f node-certs/certificate.pem ]; then
    if head -n 1 node-certs/certificate.pem | grep -q "BEGIN CERTIFICATE"; then
        echo "  ✅ certificate.pem правильный"
    else
        echo "  ❌ certificate.pem неправильный"
    fi
else
    echo "  ❌ certificate.pem не найден"
fi

if [ -f node-certs/key.pem ]; then
    if head -n 1 node-certs/key.pem | grep -q "BEGIN.*PRIVATE KEY"; then
        echo "  ✅ key.pem правильный"
    else
        echo "  ❌ key.pem неправильный (содержит: $(head -n 1 node-certs/key.pem))"
    fi
else
    echo "  ❌ key.pem не найден"
fi
echo ""

# 6. Установить права
if [ -f node-certs/certificate.pem ]; then
    chmod 644 node-certs/certificate.pem
fi
if [ -f node-certs/key.pem ]; then
    chmod 600 node-certs/key.pem
fi
echo "✅ Права установлены"
echo ""

# 7. Инструкции, если не удалось
if [ ! -f node-certs/key.pem ] || ! head -n 1 node-certs/key.pem | grep -q "BEGIN.*PRIVATE KEY"; then
    echo "❌ Не удалось автоматически извлечь ключ"
    echo ""
    echo "💡 Ручная инструкция:"
    echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online/dashboard/"
    echo "   2. Перейдите в Nodes -> ваша нода"
    echo "   3. Найдите кнопку 'Download Certificate' или 'Скачать сертификат'"
    echo "   4. Скачайте файл (обычно это один файл с расширением .pem или .crt)"
    echo "   5. Этот файл содержит и сертификат, и ключ"
    echo "   6. Скопируйте файл на ноду (например, через scp)"
    echo "   7. Запустите этот скрипт снова и укажите путь к скачанному файлу"
    echo ""
    echo "   Или вручную разделите файл:"
    echo "   - Сертификат: от -----BEGIN CERTIFICATE----- до -----END CERTIFICATE-----"
    echo "   - Ключ: от -----BEGIN PRIVATE KEY----- до -----END PRIVATE KEY-----"
    echo ""
fi


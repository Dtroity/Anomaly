#!/bin/bash

# Скрипт для исправления формата приватного ключа на ноде

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Исправление формата ключа на ноде"
echo "===================================="
echo ""

# 1. Проверить текущий формат key.pem
echo "📋 Анализ key.pem:"
if [ ! -f node-certs/key.pem ]; then
    echo "❌ key.pem не найден"
    exit 1
fi

echo "Первые 3 строки key.pem:"
head -n 3 node-certs/key.pem
echo ""

KEY_START=$(head -n 1 node-certs/key.pem)
echo "Начало файла: $KEY_START"
echo ""

# 2. Проверить различные форматы
if echo "$KEY_START" | grep -q "BEGIN PRIVATE KEY"; then
    echo "✅ Формат: PKCS#8 (-----BEGIN PRIVATE KEY-----)"
    FORMAT="PKCS8"
elif echo "$KEY_START" | grep -q "BEGIN RSA PRIVATE KEY"; then
    echo "✅ Формат: PKCS#1 (-----BEGIN RSA PRIVATE KEY-----)"
    FORMAT="PKCS1"
elif echo "$KEY_START" | grep -q "BEGIN EC PRIVATE KEY"; then
    echo "✅ Формат: EC (-----BEGIN EC PRIVATE KEY-----)"
    FORMAT="EC"
else
    echo "❌ Неизвестный формат ключа"
    echo ""
    echo "📋 Полное содержимое первых 10 строк:"
    head -n 10 node-certs/key.pem
    echo ""
    echo "💡 Возможные проблемы:"
    echo "   1. Ключ скопирован неправильно (с лишними пробелами/переносами)"
    echo "   2. Ключ в другом формате (нужна конвертация)"
    echo "   3. Это не приватный ключ, а что-то другое"
    echo ""
    read -p "Продолжить попытку исправления? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    FORMAT="UNKNOWN"
fi
echo ""

# 3. Проверить конец файла
echo "📋 Проверка конца файла:"
KEY_END=$(tail -n 1 node-certs/key.pem)
echo "Последняя строка: $KEY_END"
echo ""

if echo "$KEY_END" | grep -q "END.*PRIVATE KEY"; then
    echo "✅ Конец файла правильный"
else
    echo "⚠️  Конец файла может быть неправильным"
fi
echo ""

# 4. Проверить размер файла
KEY_SIZE=$(stat -c%s node-certs/key.pem 2>/dev/null || stat -f%z node-certs/key.pem 2>/dev/null)
echo "📋 Размер key.pem: $KEY_SIZE байт"
if [ "$KEY_SIZE" -lt 100 ]; then
    echo "  ⚠️  Файл слишком маленький, возможно, неполный"
elif [ "$KEY_SIZE" -gt 10000 ]; then
    echo "  ⚠️  Файл слишком большой, возможно, содержит лишние данные"
else
    echo "  ✅ Размер выглядит нормально"
fi
echo ""

# 5. Попытка исправления (удаление лишних пробелов/переносов)
if [ "$FORMAT" = "UNKNOWN" ]; then
    echo "🔄 Попытка исправления формата..."
    
    # Создать резервную копию
    cp node-certs/key.pem node-certs/key.pem.backup
    
    # Попробовать найти начало ключа в файле
    KEY_LINE=$(grep -n "BEGIN.*PRIVATE KEY" node-certs/key.pem | head -n 1 | cut -d: -f1)
    END_LINE=$(grep -n "END.*PRIVATE KEY" node-certs/key.pem | tail -n 1 | cut -d: -f1)
    
    if [ -n "$KEY_LINE" ] && [ -n "$END_LINE" ]; then
        echo "  Найдено начало ключа на строке $KEY_LINE"
        echo "  Найдено окончание ключа на строке $END_LINE"
        
        # Извлечь только ключ
        sed -n "${KEY_LINE},${END_LINE}p" node-certs/key.pem > node-certs/key.pem.tmp
        mv node-certs/key.pem.tmp node-certs/key.pem
        chmod 600 node-certs/key.pem
        
        echo "  ✅ Ключ извлечен (строки $KEY_LINE-$END_LINE)"
        
        # Проверить снова
        NEW_START=$(head -n 1 node-certs/key.pem)
        if echo "$NEW_START" | grep -q "BEGIN.*PRIVATE KEY"; then
            echo "  ✅ Формат исправлен!"
            FORMAT="FIXED"
        else
            echo "  ❌ Не удалось исправить формат"
            mv node-certs/key.pem.backup node-certs/key.pem
        fi
    else
        echo "  ❌ Не удалось найти начало/конец ключа в файле"
        mv node-certs/key.pem.backup node-certs/key.pem
    fi
    echo ""
fi

# 6. Финальная проверка
echo "📋 Финальная проверка:"
if head -n 1 node-certs/key.pem | grep -q "BEGIN.*PRIVATE KEY"; then
    echo "  ✅ key.pem имеет правильный формат"
    echo ""
    echo "✅ Готово! Теперь запустите:"
    echo "   ./fix-node-ssl-mount.sh"
else
    echo "  ❌ key.pem все еще имеет неправильный формат"
    echo ""
    echo "💡 Инструкции:"
    echo "   1. Откройте панель Marzban на Control Server"
    echo "   2. Перейдите в Nodes -> ваша нода"
    echo "   3. Нажмите 'Скачать сертификат' или 'Download Certificate'"
    echo "   4. Должны быть два файла: certificate.pem и key.pem"
    echo "   5. Скопируйте содержимое key.pem (должно начинаться с -----BEGIN PRIVATE KEY-----)"
    echo "   6. Создайте файл: vi node-certs/key.pem"
    echo "   7. Вставьте содержимое и сохраните"
    echo "   8. Установите права: chmod 600 node-certs/key.pem"
    echo ""
    echo "📋 Текущее содержимое key.pem (первые 5 строк):"
    head -n 5 node-certs/key.pem
    echo ""
fi


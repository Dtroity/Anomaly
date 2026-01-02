#!/bin/bash
# Установка клиентского SSL сертификата для подключения к ноде

echo "🔐 Установка клиентского SSL сертификата для ноды"
echo "=================================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

echo "📋 Инструкция по установке клиентского сертификата:"
echo ""
echo "1️⃣  Скачайте сертификат из панели Marzban:"
echo "   - Откройте: https://panel.anomaly-connect.online"
echo "   - Перейдите в Nodes -> Node 1"
echo "   - Нажмите 'Скачать сертификат'"
echo "   - Скопируйте содержимое сертификата (текст между BEGIN и END)"
echo ""
echo "2️⃣  Сохраните сертификат в файл:"
echo "   - Создайте файл: /tmp/node-client-cert.pem"
echo "   - Вставьте содержимое сертификата"
echo ""
echo "3️⃣  Запустите этот скрипт с путем к файлу:"
echo "   ./install-node-client-cert.sh /tmp/node-client-cert.pem"
echo ""

# Если передан путь к сертификату
if [ $# -gt 0 ] && [ -f "$1" ]; then
    CERT_FILE="$1"
    echo "📋 Установка сертификата из: $CERT_FILE"
    echo ""
    
    # Проверить формат сертификата
    if ! grep -q "BEGIN CERTIFICATE" "$CERT_FILE"; then
        echo "❌ Файл не является валидным PEM сертификатом"
        exit 1
    fi
    
    # Создать директории
    mkdir -p marzban_data/ssl
    mkdir -p /var/lib/marzban/ssl 2>/dev/null || true
    
    # Скопировать сертификат
    cp "$CERT_FILE" marzban_data/ssl/certificate.pem
    cp "$CERT_FILE" /var/lib/marzban/ssl/certificate.pem 2>/dev/null || true
    
    # Если есть ключ, скопировать его тоже
    KEY_FILE="${CERT_FILE%.pem}.key"
    if [ -f "$KEY_FILE" ]; then
        cp "$KEY_FILE" marzban_data/ssl/key.pem
        cp "$KEY_FILE" /var/lib/marzban/ssl/key.pem 2>/dev/null || true
        chmod 600 marzban_data/ssl/key.pem
        chmod 600 /var/lib/marzban/ssl/key.pem 2>/dev/null || true
    else
        echo "⚠️  Ключ не найден: $KEY_FILE"
        echo "   💡 Если у вас есть ключ, скопируйте его в: marzban_data/ssl/key.pem"
    fi
    
    chmod 644 marzban_data/ssl/certificate.pem
    chmod 644 /var/lib/marzban/ssl/certificate.pem 2>/dev/null || true
    
    echo "✅ Сертификат установлен"
    echo ""
    
    # Проверить, доступен ли сертификат внутри контейнера
    echo "📋 Проверка сертификата внутри контейнера Marzban:"
    if docker exec anomaly-marzban test -f /var/lib/marzban/ssl/certificate.pem; then
        echo "  ✅ Сертификат доступен в контейнере"
    else
        echo "  ⚠️  Сертификат не найден в контейнере"
        echo "  💡 Убедитесь, что volume правильно смонтирован в docker-compose.yml"
    fi
    
    echo ""
    echo "🔄 Перезапуск Marzban для применения изменений..."
    docker-compose restart marzban 2>/dev/null || docker restart anomaly-marzban 2>/dev/null || echo "  ⚠️  Не удалось перезапустить автоматически"
    
    echo ""
    echo "✅ Готово!"
    echo ""
    echo "💡 Следующие шаги:"
    echo "   1. Подождите 10-20 секунд"
    echo "   2. Вернитесь в панель Marzban: https://panel.anomaly-connect.online"
    echo "   3. Перейдите в Nodes -> Node 1 -> нажмите 'Переподключиться'"
    echo ""
else
    echo "💡 Использование:"
    echo "   ./install-node-client-cert.sh /путь/к/сертификату.pem"
    echo ""
    echo "📋 Проверка текущих сертификатов:"
    echo ""
    
    # Проверить существующие сертификаты
    if [ -f "marzban_data/ssl/certificate.pem" ]; then
        echo "  ✅ Найден: marzban_data/ssl/certificate.pem"
        echo "     Размер: $(stat -c%s marzban_data/ssl/certificate.pem) bytes"
    else
        echo "  ❌ Не найден: marzban_data/ssl/certificate.pem"
    fi
    
    if [ -f "marzban_data/ssl/key.pem" ]; then
        echo "  ✅ Найден: marzban_data/ssl/key.pem"
        echo "     Размер: $(stat -c%s marzban_data/ssl/key.pem) bytes"
    else
        echo "  ❌ Не найден: marzban_data/ssl/key.pem"
    fi
    
    echo ""
    echo "📋 Проверка внутри контейнера:"
    docker exec anomaly-marzban ls -la /var/lib/marzban/ssl/ 2>/dev/null || echo "  ⚠️  Директория не найдена или контейнер не запущен"
    echo ""
fi


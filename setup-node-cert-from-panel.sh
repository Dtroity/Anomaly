#!/bin/bash

# Скрипт для установки сертификата ноды из панели Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔧 Установка сертификата ноды из панели Marzban"
echo "================================================"
echo ""

echo "📋 Инструкция:"
echo ""
echo "  1. Откройте панель Marzban: https://panel.anomaly-connect.online"
echo "  2. Перейдите в раздел 'Marzban-Node' или 'Nodes'"
echo "  3. Найдите вашу ноду (Node 1) или создайте новую"
echo "  4. Нажмите на кнопку 'Скачать сертификат' или 'Download Certificate'"
echo "  5. Скопируйте содержимое сертификата"
echo ""
echo "  6. Вставьте сертификат ниже (нажмите Enter после вставки, затем Ctrl+D для завершения):"
echo ""

# Создать временный файл для сертификата
TEMP_CERT=$(mktemp)
cat > "$TEMP_CERT"

# Проверить, что файл не пустой
if [ ! -s "$TEMP_CERT" ]; then
    echo "  ❌ Сертификат не был вставлен"
    rm -f "$TEMP_CERT"
    exit 1
fi

# Проверить, что это валидный PEM сертификат
if ! grep -q "BEGIN CERTIFICATE" "$TEMP_CERT"; then
    echo "  ⚠️  Предупреждение: файл не содержит 'BEGIN CERTIFICATE'"
    echo "  💡 Убедитесь, что вы скопировали весь сертификат"
    read -p "  Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$TEMP_CERT"
        exit 1
    fi
fi

echo ""
echo "  ✅ Сертификат получен"
echo ""

# Спросить, на каком сервере устанавливать
echo "🌐 На каком сервере установить сертификат?"
echo "  1) Control Server (текущий сервер)"
echo "  2) Node Server (удаленный сервер)"
read -p "  Ваш выбор (1/2): " -n 1 -r
echo

if [[ $REPLY =~ ^[2]$ ]]; then
    echo ""
    echo "📤 Для установки на Node Server:"
    echo ""
    echo "  1. Скопируйте сертификат на Node Server:"
    echo "     scp $TEMP_CERT root@185.126.67.67:/tmp/node-cert.pem"
    echo ""
    echo "  2. На Node Server выполните:"
    echo "     mkdir -p /var/lib/marzban-node/ssl"
    echo "     cp /tmp/node-cert.pem /var/lib/marzban-node/ssl/certificate.pem"
    echo "     chmod 644 /var/lib/marzban-node/ssl/certificate.pem"
    echo "     docker restart anomaly-node"
    echo ""
    echo "  Или используйте скрипт на Node Server:"
    echo "     ./install-node-cert.sh /tmp/node-cert.pem"
    rm -f "$TEMP_CERT"
    exit 0
fi

# Установка на Control Server (для проверки)
echo ""
echo "📋 Сертификат будет сохранен в:"
echo "  $TEMP_CERT"
echo ""
echo "💡 Для установки на Node Server:"
echo "  1. Скопируйте этот файл на Node Server"
echo "  2. Или выполните на Node Server:"
echo "     ./install-node-cert.sh <путь_к_сертификату>"
echo ""

# Сохранить сертификат в node-certs для удобства
mkdir -p node-certs
CERT_FILE="node-certs/certificate-from-panel-$(date +%Y%m%d_%H%M%S).pem"
cp "$TEMP_CERT" "$CERT_FILE"
echo "  ✅ Сертификат сохранен в: $CERT_FILE"
echo ""

rm -f "$TEMP_CERT"

echo "✅ Готово!"
echo ""


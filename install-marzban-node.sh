#!/bin/bash

# Скрипт для автоматической установки и настройки Marzban Node
# Использует официальный образ gozargah/marzban-node

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🚀 Установка Marzban Node"
echo "========================"
echo ""

# 1. Проверить наличие Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен"
    echo "   Установите Docker: curl -fsSL https://get.docker.com | sh"
    exit 1
fi
echo "✅ Docker установлен"

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose не установлен"
    echo "   Установите Docker Compose"
    exit 1
fi
echo "✅ Docker Compose установлен"
echo ""

# 2. Создать директории
echo "📁 Создание директорий..."
mkdir -p node-data
mkdir -p node-certs
echo "✅ Директории созданы"
echo ""

# 3. Получить IP адрес ноды
NODE_IP=$(hostname -I | awk '{print $1}')
echo "📋 Параметры ноды:"
echo "  IP адрес: $NODE_IP"
echo ""

# 4. Проверить/создать .env.node
echo "📋 Проверка .env.node..."
if [ ! -f .env.node ]; then
    echo "⚠️  .env.node не найден, создаю из шаблона..."
    if [ -f env.node.template ]; then
        cp env.node.template .env.node
        echo "✅ .env.node создан из шаблона"
    else
        echo "❌ env.node.template не найден"
        exit 1
    fi
else
    echo "✅ .env.node существует"
fi
echo ""

# 5. Получить сертификат из панели
echo "📋 Настройка SSL сертификата..."
echo ""
echo "💡 Инструкция по получению сертификата:"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online/dashboard/"
echo "   2. Перейдите в раздел 'Nodes' (Ноды)"
echo "   3. Найдите вашу ноду или создайте новую"
echo "   4. Нажмите 'Скачать сертификат' (Download Certificate)"
echo "   5. Скопируйте содержимое сертификата"
echo ""
read -p "Нажмите Enter после получения сертификата..."

# Проверить, есть ли уже сертификат
if [ -f node-certs/ssl_client_cert.pem ]; then
    echo "  ✅ Сертификат уже существует: node-certs/ssl_client_cert.pem"
    read -p "Использовать существующий сертификат? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "  Создайте файл node-certs/ssl_client_cert.pem с содержимым сертификата"
        read -p "Нажмите Enter после создания файла..."
    fi
else
    echo "  Создайте файл node-certs/ssl_client_cert.pem с содержимым сертификата"
    echo "  Команда: vi node-certs/ssl_client_cert.pem"
    read -p "Нажмите Enter после создания файла..."
fi

# Проверить наличие сертификата
if [ ! -f node-certs/ssl_client_cert.pem ]; then
    echo "❌ Сертификат не найден: node-certs/ssl_client_cert.pem"
    echo "   Создайте файл и запустите скрипт снова"
    exit 1
fi

# Проверить формат сертификата
if ! head -n 1 node-certs/ssl_client_cert.pem | grep -q "BEGIN CERTIFICATE"; then
    echo "⚠️  Предупреждение: сертификат может иметь неправильный формат"
    echo "   Должно начинаться с: -----BEGIN CERTIFICATE-----"
fi

chmod 644 node-certs/ssl_client_cert.pem
echo "✅ Сертификат настроен"
echo ""

# 6. Обновить docker-compose.node.yml для marzban-node
echo "🔄 Обновление docker-compose.node.yml..."
cat > docker-compose.node.yml << 'EOF'
version: '3.8'

# Anomaly VPN - Node (VPS #2)
# Использует официальный образ marzban-node

services:
  # Marzban Node - подключается к Control Server
  marzban-node:
    image: gozargah/marzban-node:latest
    container_name: anomaly-node
    restart: unless-stopped
    network_mode: host
    environment:
      # SSL сертификат клиента для подключения к Control Server
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      # Использовать REST API протокол
      SERVICE_PROTOCOL: "rest"
    volumes:
      - ./node-data:/var/lib/marzban-node
      - ./node-certs/ssl_client_cert.pem:/var/lib/marzban-node/ssl_client_cert.pem:ro
    # network_mode: host позволяет ноде использовать порты хоста напрямую
    # Порты: 443 (VLESS Reality), 80 (Fallback), 62050 (API)
EOF
echo "✅ docker-compose.node.yml обновлен"
echo ""

# 7. Копировать сертификат в node-data (для доступа внутри контейнера)
echo "📁 Копирование сертификата в node-data..."
mkdir -p node-data
cp node-certs/ssl_client_cert.pem node-data/ssl_client_cert.pem
chmod 644 node-data/ssl_client_cert.pem
echo "✅ Сертификат скопирован"
echo ""

# 8. Остановить старый контейнер (если есть)
echo "🔄 Остановка старого контейнера..."
docker-compose -f docker-compose.node.yml down 2>/dev/null || true
docker stop anomaly-node 2>/dev/null || true
docker rm anomaly-node 2>/dev/null || true
echo "✅ Старый контейнер остановлен"
echo ""

# 9. Запустить marzban-node
echo "🚀 Запуск Marzban Node..."
docker-compose -f docker-compose.node.yml pull
docker-compose -f docker-compose.node.yml up -d
echo "⏳ Ожидание запуска (15 секунд)..."
sleep 15
echo ""

# 10. Проверить статус
echo "📊 Статус контейнера:"
docker-compose -f docker-compose.node.yml ps
echo ""

# 11. Проверить логи
echo "📋 Логи Marzban Node (последние 30 строк):"
docker-compose -f docker-compose.node.yml logs --tail=30 marzban-node
echo ""

# 12. Проверить доступность
echo "🌐 Проверка доступности:"
if docker-compose -f docker-compose.node.yml ps marzban-node | grep -q "Up"; then
    echo "  ✅ Контейнер запущен"
    
    # Проверить порты
    if netstat -tlnp 2>/dev/null | grep -q ":443 " || ss -tlnp 2>/dev/null | grep -q ":443 "; then
        echo "  ✅ Порт 443 открыт"
    else
        echo "  ⚠️  Порт 443 не найден (может быть нормально, если используется network_mode: host)"
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":80 " || ss -tlnp 2>/dev/null | grep -q ":80 "; then
        echo "  ✅ Порт 80 открыт"
    else
        echo "  ⚠️  Порт 80 не найден"
    fi
else
    echo "  ❌ Контейнер не запущен"
fi
echo ""

# 13. Информация для настройки в панели
echo "✅ Установка завершена!"
echo ""
echo "📝 Следующие шаги:"
echo "   1. Откройте панель Marzban: https://panel.anomaly-connect.online/dashboard/"
echo "   2. Перейдите в раздел 'Nodes' (Ноды)"
echo "   3. Добавьте новую ноду или отредактируйте существующую:"
echo "      - Имя: Node 1 (или ваше имя)"
echo "      - Адрес: $NODE_IP"
echo "      - Порт: 62050"
echo "      - API порт: 62051"
echo "      - Коэффициент использования: 1"
echo "   4. Нажмите 'Добавить узел' или 'Сохранить'"
echo "   5. Нода должна автоматически подключиться"
echo ""
echo "💡 Если нода не подключается:"
echo "   - Проверьте логи: docker-compose -f docker-compose.node.yml logs -f marzban-node"
echo "   - Убедитесь, что сертификат правильный"
echo "   - Проверьте, что Control Server доступен с ноды"
echo ""


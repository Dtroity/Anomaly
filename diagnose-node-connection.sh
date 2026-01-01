#!/bin/bash

# Скрипт для диагностики проблемы подключения ноды

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🔍 Диагностика подключения ноды Marzban"
echo "========================================"
echo ""

NODE_IP="185.126.67.67"
NODE_PORT="62050"
NODE_API_PORT="62051"

# 1. Проверка доступности ноды с Control Server
echo "1️⃣ Проверка доступности ноды с Control Server:"
echo ""

# Ping
echo "   📡 Ping ноды ($NODE_IP):"
if ping -c 3 -W 2 "$NODE_IP" > /dev/null 2>&1; then
    echo "      ✅ IP адрес доступен"
else
    echo "      ❌ IP адрес недоступен"
    echo "         Проверьте, что нода запущена и доступна"
fi
echo ""

# Проверка порта 62050
echo "   🔌 Проверка порта $NODE_PORT (marzban-node):"
if timeout 5 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_PORT" 2>/dev/null; then
    echo "      ✅ Порт $NODE_PORT открыт и доступен"
else
    echo "      ❌ Порт $NODE_PORT недоступен"
    echo "         Проверьте:"
    echo "         - Запущен ли marzban-node на ноде"
    echo "         - Открыт ли порт $NODE_PORT в файрволе на ноде"
    echo "         - Правильный ли IP адрес"
fi
echo ""

# Проверка порта 62051
echo "   🔌 Проверка порта $NODE_API_PORT (API):"
if timeout 5 bash -c "echo > /dev/tcp/$NODE_IP/$NODE_API_PORT" 2>/dev/null; then
    echo "      ✅ Порт $NODE_API_PORT открыт и доступен"
else
    echo "      ⚠️  Порт $NODE_API_PORT недоступен (может быть нормально, если используется другой порт)"
fi
echo ""

# 2. Проверка конфигурации ноды в Marzban
echo "2️⃣ Проверка конфигурации ноды в Marzban:"
echo ""

if docker-compose ps marzban | grep -q "Up"; then
    echo "   📋 Список нод в Marzban:"
    docker-compose exec -T marzban marzban-cli node list 2>/dev/null || echo "      ⚠️  Не удалось получить список нод"
    echo ""
    
    echo "   💡 Проверьте в панели Marzban:"
    echo "      - Адрес ноды должен быть: $NODE_IP"
    echo "      - Порт должен быть: $NODE_PORT"
    echo "      - API порт должен быть: $NODE_API_PORT"
    echo ""
else
    echo "   ❌ Marzban не запущен"
    echo ""
fi

# 3. Проверка DNS
echo "3️⃣ Проверка DNS:"
echo "   🔍 Обратное разрешение DNS для $NODE_IP:"
REVERSE_DNS=$(dig +short -x "$NODE_IP" 2>/dev/null || getent hosts "$NODE_IP" 2>/dev/null | awk '{print $2}')
if [ -n "$REVERSE_DNS" ]; then
    echo "      ✅ DNS: $REVERSE_DNS"
else
    echo "      ⚠️  Обратное DNS разрешение недоступно (может быть нормально)"
fi
echo ""

# 4. Проверка подключения через curl
echo "4️⃣ Проверка подключения к marzban-node:"
echo "   🔗 Попытка подключения к http://$NODE_IP:$NODE_PORT:"
RESPONSE=$(timeout 5 curl -s -k -o /dev/null -w "%{http_code}" "http://$NODE_IP:$NODE_PORT" 2>/dev/null || echo "000")
if [ "$RESPONSE" != "000" ] && [ "$RESPONSE" != "" ]; then
    echo "      ✅ Подключение успешно (HTTP $RESPONSE)"
else
    echo "      ❌ Не удалось подключиться"
    echo "         Возможные причины:"
    echo "         - marzban-node не запущен на ноде"
    echo "         - Порт $NODE_PORT закрыт файрволом"
    echo "         - Неправильный IP адрес"
fi
echo ""

# 5. Инструкции для проверки на ноде
echo "5️⃣ Что проверить на ноде ($NODE_IP):"
echo ""
echo "   Выполните на ноде следующие команды:"
echo ""
echo "   # 1. Проверить, запущен ли marzban-node:"
echo "   docker ps | grep marzban-node"
echo "   # или"
echo "   systemctl status marzban-node"
echo ""
echo "   # 2. Проверить логи marzban-node:"
echo "   docker logs marzban-node"
echo "   # или"
echo "   journalctl -u marzban-node -n 50"
echo ""
echo "   # 3. Проверить, слушает ли порт 62050:"
echo "   netstat -tlnp | grep 62050"
echo "   # или"
echo "   ss -tlnp | grep 62050"
echo ""
echo "   # 4. Проверить файрвол:"
echo "   ufw status | grep 62050"
echo "   # или"
echo "   iptables -L -n | grep 62050"
echo ""
echo "   # 5. Проверить конфигурацию .env.node:"
echo "   cat .env.node | grep -E 'CONTROL_SERVER_URL|SSL_CLIENT_CERT_FILE|UVICORN_HOST|UVICORN_PORT'"
echo ""

# 6. Рекомендации
echo "6️⃣ Рекомендации:"
echo ""
echo "   Если порт недоступен:"
echo "   1. На ноде откройте порт в файрволе:"
echo "      ufw allow 62050/tcp"
echo "      # или"
echo "      iptables -A INPUT -p tcp --dport 62050 -j ACCEPT"
echo ""
echo "   2. Убедитесь, что marzban-node слушает на 0.0.0.0, а не на 127.0.0.1:"
echo "      В .env.node должно быть: UVICORN_HOST=0.0.0.0"
echo ""
echo "   3. Проверьте, что CONTROL_SERVER_URL правильный:"
echo "      CONTROL_SERVER_URL=https://panel.anomaly-connect.online"
echo "      # или IP адрес Control Server"
echo ""
echo "   4. Перезапустите marzban-node на ноде:"
echo "      docker-compose -f docker-compose.node.yml restart marzban-node"
echo ""

echo "✅ Диагностика завершена!"
echo ""


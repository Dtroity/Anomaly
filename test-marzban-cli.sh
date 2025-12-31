#!/bin/bash

# Скрипт для проверки доступных команд Marzban в контейнере

set -e

echo "🔍 Проверка доступных команд Marzban"
echo "===================================="
echo ""

cd /opt/Anomaly

# Проверить, какие команды доступны
echo "📋 Проверка команд в контейнере:"
echo ""

echo "1. Проверка marzban-cli:"
docker-compose exec -T marzban which marzban-cli || echo "   ❌ marzban-cli не найден"

echo ""
echo "2. Проверка python -m cli.admin:"
docker-compose exec -T marzban python -m cli.admin --help 2>&1 | head -5 || echo "   ❌ python -m cli.admin не работает"

echo ""
echo "3. Проверка содержимого /code:"
docker-compose exec -T marzban ls -la /code/ | grep -E "cli|marzban" || echo "   ❌ Не найдено"

echo ""
echo "4. Проверка /usr/bin:"
docker-compose exec -T marzban ls -la /usr/bin/ | grep -E "marzban|cli" || echo "   ❌ Не найдено"

echo ""
echo "5. Попытка выполнить команду напрямую:"
docker-compose exec -T marzban bash -c "cd /code && python -m cli.admin list" 2>&1 | head -10 || echo "   ❌ Ошибка"


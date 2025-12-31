#!/bin/bash

# Скрипт для создания первого администратора в Marzban

set -e

echo "👤 Создание администратора Marzban"
echo "==================================="
echo ""

cd /opt/Anomaly

# 1. Проверить, запущен ли Marzban
if ! docker-compose ps marzban | grep -q "Up"; then
    echo "❌ Marzban не запущен. Запустите его сначала:"
    echo "   docker-compose up -d marzban"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Проверить, есть ли уже администраторы
echo "📋 Проверка существующих администраторов..."
# Используем Python напрямую для выполнения CLI команд
EXISTING_ADMINS=$(docker-compose exec -T marzban python -m cli.admin list 2>/dev/null | grep -v "Username" | grep -v "^$" | wc -l || echo "0")

if [ "$EXISTING_ADMINS" -gt 0 ]; then
    echo "⚠️  Найдены существующие администраторы:"
    docker-compose exec marzban python -m cli.admin list
    echo ""
    read -p "Создать еще одного администратора? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено."
        exit 0
    fi
fi

# 3. Запросить данные для нового администратора
echo "📝 Введите данные для нового администратора:"
echo ""

read -p "Имя пользователя (по умолчанию: root): " USERNAME
USERNAME=${USERNAME:-root}

read -sp "Пароль: " PASSWORD
echo ""

read -sp "Подтвердите пароль: " PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "❌ Пароли не совпадают!"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "❌ Пароль не может быть пустым!"
    exit 1
fi

read -p "Сделать супер-администратором (sudo)? (y/n, по умолчанию: y): " -n 1 -r
echo ""
IS_SUDO="--is-sudo"
if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
    IS_SUDO=""
fi

# 4. Создать администратора
echo ""
echo "🔄 Создание администратора..."

# Используем Python напрямую с передачей пароля через переменную окружения
if docker-compose exec -T -e MARZBAN_ADMIN_PASSWORD="$PASSWORD" marzban python -m cli.admin create \
    --username "${USERNAME:-root}" \
    $IS_SUDO \
    --password "$PASSWORD" 2>&1; then
    echo ""
    echo "✅ Администратор '${USERNAME:-root}' успешно создан!"
    echo ""
    echo "📋 Данные для входа:"
    echo "   URL: https://panel.anomaly-connect.online"
    echo "   Имя пользователя: ${USERNAME:-root}"
    echo "   Пароль: (введенный вами)"
    echo ""
else
    echo ""
    echo "❌ Ошибка при создании администратора"
    echo "   Возможно, администратор с таким именем уже существует"
    echo ""
    echo "💡 Попробуйте создать администратора вручную:"
    echo "   docker-compose exec marzban python -m cli.admin create --is-sudo"
    exit 1
fi

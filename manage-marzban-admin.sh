#!/bin/bash

# Скрипт для управления администраторами Marzban

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "👤 Управление администраторами Marzban"
echo "======================================="
echo ""

# 1. Проверить, запущен ли Marzban
if ! docker-compose ps marzban | grep -q "Up"; then
    echo "❌ Marzban не запущен. Запустите его сначала:"
    echo "   docker-compose up -d marzban"
    exit 1
fi

echo "✅ Marzban запущен"
echo ""

# 2. Показать меню
echo "Выберите действие:"
echo "  1) Список администраторов"
echo "  2) Создать нового администратора"
echo "  3) Обновить администратора"
echo "  4) Удалить администратора"
echo "  5) Войти в панель Marzban (откроется в браузере)"
echo ""
read -p "Ваш выбор (1-5): " choice

case $choice in
    1)
        echo ""
        echo "📋 Список администраторов:"
        docker-compose exec marzban marzban-cli admin list
        ;;
    2)
        echo ""
        echo "📝 Создание нового администратора:"
        read -p "Имя пользователя: " username
        read -sp "Пароль: " password
        echo ""
        read -sp "Подтвердите пароль: " password_confirm
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            echo "❌ Пароли не совпадают!"
            exit 1
        fi
        
        read -p "Сделать супер-администратором (sudo)? (y/n, по умолчанию: y): " -n 1 -r
        echo ""
        IS_SUDO="--sudo"
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
            IS_SUDO=""
        fi
        
        read -p "Telegram ID (опционально, можно оставить пустым): " telegram_id
        
        echo ""
        echo "🔄 Создание администратора..."
        if docker-compose exec -T marzban marzban-cli admin create \
            --username "$username" \
            $IS_SUDO \
            --password "$password" \
            --telegram-id "$telegram_id" 2>&1; then
            echo ""
            echo "✅ Администратор '$username' успешно создан!"
        else
            echo ""
            echo "❌ Ошибка при создании администратора"
        fi
        ;;
    3)
        echo ""
        echo "📝 Обновление администратора:"
        read -p "Имя пользователя для обновления: " username
        
        echo ""
        echo "Что вы хотите обновить?"
        echo "  1) Пароль"
        echo "  2) Telegram ID"
        echo "  3) Права (sudo)"
        read -p "Ваш выбор (1-3): " update_choice
        
        case $update_choice in
            1)
                read -sp "Новый пароль: " new_password
                echo ""
                read -sp "Подтвердите пароль: " new_password_confirm
                echo ""
                
                if [ "$new_password" != "$new_password_confirm" ]; then
                    echo "❌ Пароли не совпадают!"
                    exit 1
                fi
                
                echo "🔄 Обновление пароля..."
                docker-compose exec -T marzban marzban-cli admin update \
                    --username "$username" \
                    --password "$new_password" 2>&1
                ;;
            2)
                read -p "Новый Telegram ID: " new_telegram_id
                echo "🔄 Обновление Telegram ID..."
                docker-compose exec -T marzban marzban-cli admin update \
                    --username "$username" \
                    --telegram-id "$new_telegram_id" 2>&1
                ;;
            3)
                read -p "Сделать супер-администратором? (y/n): " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    docker-compose exec -T marzban marzban-cli admin update \
                        --username "$username" \
                        --sudo true 2>&1
                else
                    docker-compose exec -T marzban marzban-cli admin update \
                        --username "$username" \
                        --sudo false 2>&1
                fi
                ;;
            *)
                echo "❌ Неверный выбор"
                exit 1
                ;;
        esac
        ;;
    4)
        echo ""
        echo "🗑️  Удаление администратора:"
        read -p "Имя пользователя для удаления: " username
        read -p "Вы уверены, что хотите удалить '$username'? (yes/no): " confirm
        
        if [ "$confirm" = "yes" ]; then
            echo "🔄 Удаление администратора..."
            docker-compose exec -T marzban marzban-cli admin delete \
                --username "$username" \
                --yes-to-all 2>&1
        else
            echo "❌ Отменено"
        fi
        ;;
    5)
        echo ""
        echo "🌐 Открытие панели Marzban..."
        echo "   URL: https://panel.anomaly-connect.online"
        echo ""
        echo "💡 Если вы на сервере, скопируйте URL выше и откройте в браузере"
        echo "   Или используйте SSH туннель:"
        echo "   ssh -L 8443:localhost:443 root@YOUR_SERVER_IP"
        echo "   Затем откройте: https://localhost:8443"
        ;;
    *)
        echo "❌ Неверный выбор"
        exit 1
        ;;
esac

echo ""
echo "✅ Готово!"


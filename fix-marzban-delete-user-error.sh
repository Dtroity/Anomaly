#!/bin/bash

# Скрипт для исправления ошибки удаления пользователя в Marzban
# Проблема: Admin.model_validate(dbuser.admin) падает, если dbuser.admin is None

echo "🔧 Исправление ошибки удаления пользователя в Marzban"
echo "====================================================="
echo ""

# Проверка, что мы на Control Server
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен на Control Server"
    exit 1
fi

echo "📋 Поиск файла user.py в контейнере Marzban..."
FILE_PATH=$(docker exec anomaly-marzban find /code -name "user.py" -path "*/routers/user.py" 2>/dev/null | head -1)

if [ -z "$FILE_PATH" ]; then
    echo "❌ Не удалось найти файл /code/app/routers/user.py"
    exit 1
fi

echo "   Найден: $FILE_PATH"
echo ""

echo "📋 Создание резервной копии..."
docker exec anomaly-marzban cp "$FILE_PATH" "${FILE_PATH}.backup"
echo "   ✅ Резервная копия создана: ${FILE_PATH}.backup"
echo ""

echo "🔧 Применение патча..."
# Исправляем строку 152: добавляем проверку на None перед валидацией
docker exec anomaly-marzban python3 << 'PYTHON_SCRIPT'
file_path = "/code/app/routers/user.py"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    modified = False
    
    # Ищем строку с проблемой
    for i, line in enumerate(lines):
        if 'Admin.model_validate(dbuser.admin)' in line and 'user_admin=' in line:
            # Заменяем проблемную часть
            new_line = line.replace(
                'Admin.model_validate(dbuser.admin)',
                'Admin.model_validate(dbuser.admin) if dbuser.admin else None'
            )
            lines[i] = new_line
            modified = True
            print(f"✅ Найдена и исправлена строка {i+1}")
            break
    
    if modified:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        print("✅ Патч применен успешно")
    else:
        print("⚠️  Проблемная строка не найдена.")
        print("   Проверяем содержимое файла вокруг функции remove_user:")
        # Показываем контекст
        in_remove_user = False
        for i, line in enumerate(lines):
            if 'def remove_user' in line:
                in_remove_user = True
            if in_remove_user:
                print(f"{i+1:4d}: {line.rstrip()}")
                if 'return {' in line and '"detail"' in line:
                    break
        print("\n   Возможно, файл уже исправлен или имеет другую структуру.")
            
except Exception as e:
    print(f"❌ Ошибка при применении патча: {e}")
    import traceback
    traceback.print_exc()
    exit(1)
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    echo ""
    echo "🔄 Перезапуск Marzban для применения изменений..."
    docker-compose restart marzban
    echo ""
    echo "⏳ Ожидание запуска (10 секунд)..."
    sleep 10
    echo ""
    echo "✅ Исправление завершено!"
    echo ""
    echo "💡 Теперь попробуйте удалить пользователя через панель"
else
    echo ""
    echo "❌ Не удалось применить патч автоматически"
    echo ""
    echo "💡 Альтернативное решение:"
    echo "   1. Проверьте содержимое файла:"
    echo "      docker exec -it anomaly-marzban cat /code/app/routers/user.py | grep -A 5 'def remove_user'"
    echo ""
    echo "   2. Вручную исправьте строку 152:"
    echo "      Замените: Admin.model_validate(dbuser.admin)"
    echo "      На: Admin.model_validate(dbuser.admin) if dbuser.admin else None"
    echo ""
    echo "   3. Перезапустите Marzban: docker-compose restart marzban"
fi


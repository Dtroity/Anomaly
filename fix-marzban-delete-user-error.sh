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
import re

file_path = "/code/app/routers/user.py"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Ищем проблемную строку
    old_pattern = r'(\s+)(bg\.add_task\(\s+report\.user_deleted, username=dbuser\.username, user_admin=Admin\.model_validate\(dbuser\.admin\), by=admin\s+\))'
    
    # Заменяем на безопасную версию с проверкой на None
    new_code = r'\1bg.add_task(\n\1    report.user_deleted, username=dbuser.username, user_admin=Admin.model_validate(dbuser.admin) if dbuser.admin else None, by=admin\n\1)'
    
    if re.search(old_pattern, content):
        content = re.sub(old_pattern, new_code, content)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print("✅ Патч применен успешно")
    else:
        # Попробуем другой паттерн (многострочный)
        old_pattern2 = r'(\s+)(bg\.add_task\(\s+report\.user_deleted, username=dbuser\.username, user_admin=Admin\.model_validate\(dbuser\.admin\), by=admin\s+\))'
        
        # Или попробуем найти по контексту
        lines = content.split('\n')
        modified = False
        
        for i, line in enumerate(lines):
            if 'Admin.model_validate(dbuser.admin)' in line and 'user_admin=' in line:
                # Заменяем строку
                lines[i] = line.replace(
                    'Admin.model_validate(dbuser.admin)',
                    'Admin.model_validate(dbuser.admin) if dbuser.admin else None'
                )
                modified = True
                break
        
        if modified:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines))
            print("✅ Патч применен успешно (метод 2)")
        else:
            print("⚠️  Проблемная строка не найдена. Возможно, файл уже исправлен или имеет другую структуру.")
            print("   Проверьте файл вручную:")
            print(f"   docker exec -it anomaly-marzban cat {file_path} | grep -A 2 -B 2 'user_deleted'")
            
except Exception as e:
    print(f"❌ Ошибка при применении патча: {e}")
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


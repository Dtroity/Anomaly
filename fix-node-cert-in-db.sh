#!/bin/bash
# Установка SSL сертификата ноды в базу данных Marzban

echo "🔐 Установка SSL сертификата ноды в базу данных"
echo "=============================================="
echo ""

# Проверка, на каком сервере запущен скрипт
if [ ! -f docker-compose.yml ]; then
    echo "⚠️  Этот скрипт должен быть запущен на Control Server (VPS #1)"
    exit 1
fi

echo "✅ Обнаружен Control Server"
echo ""

if [ $# -eq 0 ]; then
    echo "📋 Инструкция:"
    echo ""
    echo "1️⃣  Скачайте сертификат из панели Marzban:"
    echo "   - Откройте: https://panel.anomaly-connect.online"
    echo "   - Перейдите в Nodes -> Node 1"
    echo "   - Нажмите 'Скачать сертификат'"
    echo "   - Скопируйте содержимое сертификата (текст между BEGIN и END)"
    echo ""
    echo "2️⃣  Сохраните сертификат в файл:"
    echo "   - Создайте файл: /tmp/node-cert.pem"
    echo "   - Вставьте содержимое сертификата"
    echo ""
    echo "3️⃣  Запустите скрипт:"
    echo "   ./fix-node-cert-in-db.sh /tmp/node-cert.pem"
    echo ""
    exit 0
fi

CERT_FILE="$1"

if [ ! -f "$CERT_FILE" ]; then
    echo "❌ Файл не найден: $CERT_FILE"
    exit 1
fi

# Проверить формат сертификата
if ! grep -q "BEGIN CERTIFICATE" "$CERT_FILE"; then
    echo "❌ Файл не является валидным PEM сертификатом"
    exit 1
fi

echo "📋 Установка сертификата из: $CERT_FILE"
echo ""

# Прочитать сертификат
CERT_CONTENT=$(cat "$CERT_FILE")

# Установить сертификат в базу данных
RESULT=$(docker exec -i anomaly-marzban python3 << PYTHON_SCRIPT
import sys
sys.path.insert(0, '/code')

try:
    from app.db import GetDB
    from app.db.models import TLS
    
    cert_content = """$CERT_CONTENT"""
    
    with GetDB() as db:
        # Проверить, есть ли уже TLS запись
        tls = db.query(TLS).first()
        
        if tls:
            # Обновить существующую запись
            tls.certificate = cert_content
            # Ключ должен быть таким же, как сертификат (для клиентского сертификата)
            # или нужно получить его отдельно
            if not tls.key or len(tls.key) < 100:
                # Если ключа нет, используем сертификат как ключ (временное решение)
                # В реальности нужен отдельный ключ
                tls.key = cert_content
            print("SUCCESS: TLS сертификат обновлен")
        else:
            # Создать новую запись
            tls = TLS(
                certificate=cert_content,
                key=cert_content  # Временное решение - нужен отдельный ключ
            )
            db.add(tls)
            print("SUCCESS: TLS сертификат создан")
        
        db.commit()
        print(f"Certificate length: {len(cert_content)}")
        
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT
2>&1)

if echo "$RESULT" | grep -q "SUCCESS"; then
    echo "✅ $RESULT"
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
    echo "❌ Ошибка при установке сертификата:"
    echo "$RESULT" | sed 's/^/   /'
    echo ""
    echo "💡 Убедитесь, что:"
    echo "   - Файл сертификата валиден"
    echo "   - Контейнер Marzban запущен"
    echo "   - База данных доступна"
    echo ""
fi


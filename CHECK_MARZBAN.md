# 🔍 Диагностика проблемы с Marzban

## Проблема
Marzban находится в состоянии `Restarting` - постоянно перезапускается.

## Команды для диагностики

### 1. Проверить логи Marzban
```bash
docker-compose logs marzban
```

### 2. Проверить последние 50 строк логов
```bash
docker-compose logs --tail=50 marzban
```

### 3. Проверить, существует ли xray_config.json
```bash
docker-compose exec marzban ls -la /var/lib/marzban/
```

### 4. Создать xray_config.json вручную
```bash
docker-compose exec marzban bash -c 'echo "{\"log\":{\"loglevel\":\"warning\"},\"routing\":{\"rules\":[]},\"inbounds\":[],\"outbounds\":[{\"protocol\":\"freedom\",\"tag\":\"DIRECT\"}]}" > /var/lib/marzban/xray_config.json'
```

### 5. Проверить подключение к базе данных
```bash
docker-compose exec marzban env | grep DATABASE
```

### 6. Проверить переменные окружения Marzban
```bash
docker-compose exec marzban env | grep -E "MARZBAN|DATABASE|XRAY"
```

## Возможные причины

1. **Отсутствует xray_config.json** - Marzban не может найти конфигурационный файл Xray
2. **Проблемы с базой данных** - Неправильный DATABASE_URL или база не готова
3. **Проблемы с миграциями Alembic** - Ошибки при выполнении `alembic upgrade head`
4. **Проблемы с правами доступа** - Нет прав на запись в `/var/lib/marzban`

## Решение

После проверки логов выполните:

```bash
# Остановить Marzban
docker-compose stop marzban

# Создать директорию и файл конфигурации
docker-compose run --rm marzban mkdir -p /var/lib/marzban
docker-compose run --rm marzban bash -c 'echo "{\"log\":{\"loglevel\":\"warning\"},\"routing\":{\"rules\":[]},\"inbounds\":[],\"outbounds\":[{\"protocol\":\"freedom\",\"tag\":\"DIRECT\"}]}" > /var/lib/marzban/xray_config.json'

# Проверить .env.marzban
cat .env.marzban | grep DATABASE_URL

# Запустить снова
docker-compose up -d marzban

# Проверить логи
docker-compose logs -f marzban
```


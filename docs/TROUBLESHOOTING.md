# 🆘 Решение проблем - Anomaly Connect

## Проблема: `env.before-ssl.template` не найден

### Решение 1: Использовать скрипт CREATE_ENV.sh

```bash
cd /opt/Anomaly
chmod +x CREATE_ENV.sh
./CREATE_ENV.sh
nano .env
```

### Решение 2: Создать файл вручную

```bash
cd /opt/Anomaly
nano .env
```

Вставьте содержимое из `env.before-ssl.template` (см. файл в репозитории) или используйте минимальную конфигурацию:

```env
# Telegram Bot
BOT_TOKEN=your_bot_token_here
ADMIN_IDS=your_telegram_id

# Database
DB_NAME=anomaly
DB_USER=anomaly
DB_PASSWORD=strong_password_here
DB_HOST=db
DB_PORT=5432

# Marzban
MARZBAN_API_URL=http://marzban:62050
MARZBAN_USERNAME=root
MARZBAN_PASSWORD=strong_password_here

# Payments
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key
YOOKASSA_TEST_MODE=true

# Application
APP_NAME=Anomaly Connect
APP_URL=http://api.anomaly-connect.online
PANEL_URL=http://panel.anomaly-connect.online
API_SECRET_KEY=$(openssl rand -hex 32)

# VPN Settings
DEFAULT_TRAFFIC_LIMIT_GB=100
DEFAULT_MAX_DEVICES=3

# Trial
FREE_TRIAL_DAYS=7
FREE_TRIAL_TRAFFIC_GB=5

# Nodes
NODES_CONFIG=[]
```

### Решение 3: Проверить наличие файла в репозитории

```bash
cd /opt/Anomaly
ls -la *.template
ls -la env*
```

Если файл отсутствует, создайте его из репозитория или используйте CREATE_ENV.sh.

## Проблема: DNS не распространяется

### Проверка DNS

```bash
# Проверка через nslookup
nslookup api.anomaly-connect.online

# Проверка через dig
dig api.anomaly-connect.online

# Проверка через разные DNS серверы
nslookup api.anomaly-connect.online 8.8.8.8
nslookup api.anomaly-connect.online 1.1.1.1
```

### Решение

- Подождите 30-60 минут после создания DNS записей
- Проверьте правильность IP адреса в DNS записях (должен быть 72.56.79.212)
- Убедитесь, что TTL не слишком большой (рекомендуется 600)

## Проблема: SSL сертификат не получается

### Ошибка: "Failed to obtain certificate"

**Причины:**
- DNS не распространился
- Порт 80 закрыт
- Домен не указывает на правильный IP

**Решение:**

```bash
# 1. Проверьте DNS
nslookup api.anomaly-connect.online

# 2. Откройте порт 80
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 3. Проверьте, что Nginx остановлен для standalone режима
cd /opt/Anomaly
docker-compose stop nginx

# 4. Получите сертификат вручную
sudo certbot certonly --standalone \
  -d anomaly-connect.online \
  -d api.anomaly-connect.online \
  -d panel.anomaly-connect.online \
  --email your-email@example.com \
  --agree-tos
```

## Проблема: Docker контейнеры не запускаются

### Проверка статуса

```bash
cd /opt/Anomaly
docker-compose ps
docker-compose logs
```

### Решение

```bash
# Пересобрать контейнеры
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Проверить логи конкретного сервиса
docker-compose logs -f bot
docker-compose logs -f api
docker-compose logs -f db
```

## Проблема: Бот не отвечает в Telegram

### Проверка

```bash
# 1. Проверьте BOT_TOKEN в .env
cd /opt/Anomaly
grep BOT_TOKEN .env

# 2. Проверьте логи бота
docker-compose logs bot

# 3. Проверьте статус контейнера
docker-compose ps bot
```

### Решение

```bash
# 1. Убедитесь, что BOT_TOKEN правильный (получите у @BotFather)
# 2. Перезапустите бота
docker-compose restart bot

# 3. Проверьте подключение к базе данных
docker-compose exec db psql -U anomaly -d anomaly -c "SELECT 1;"
```

## Проблема: API недоступен

### Проверка

```bash
# Проверка через curl
curl http://api.anomaly-connect.online
curl https://api.anomaly-connect.online

# Проверка логов Nginx
docker-compose logs nginx

# Проверка логов API
docker-compose logs api
```

### Решение

```bash
# 1. Проверьте конфигурацию Nginx
docker-compose exec nginx nginx -t

# 2. Перезагрузите Nginx
docker-compose restart nginx

# 3. Проверьте, что API контейнер запущен
docker-compose ps api
docker-compose logs api
```

## Проблема: База данных не подключается

### Проверка

```bash
# Проверка подключения к БД
docker-compose exec db psql -U anomaly -d anomaly -c "SELECT version();"

# Проверка логов БД
docker-compose logs db
```

### Решение

```bash
# 1. Проверьте пароль в .env (DB_PASSWORD)
# 2. Перезапустите БД
docker-compose restart db

# 3. Проверьте, что БД контейнер запущен
docker-compose ps db
```

## Проблема: Marzban не доступен

### Проверка

```bash
# Проверка внутри контейнера
docker-compose exec marzban curl http://localhost:62050

# Проверка логов
docker-compose logs marzban
```

### Решение

```bash
# 1. Проверьте .env.marzban
cat .env.marzban

# 2. Перезапустите Marzban
docker-compose restart marzban

# 3. Проверьте подключение к БД из Marzban
docker-compose exec marzban python -c "import psycopg2; print('OK')"
```

## Полезные команды для диагностики

```bash
# Просмотр всех логов
docker-compose logs -f

# Статус всех контейнеров
docker-compose ps

# Использование ресурсов
docker stats

# Проверка сетевых подключений
docker network inspect anomaly-network

# Проверка портов
netstat -tulpn | grep -E '80|443|5432|62050'

# Проверка дискового пространства
df -h

# Проверка использования памяти
free -h
```

## Полный сброс (если ничего не помогает)

```bash
cd /opt/Anomaly

# Остановить все контейнеры
docker-compose down

# Удалить все контейнеры и volumes (ОСТОРОЖНО: удалит данные!)
docker-compose down -v

# Пересобрать все
docker-compose build --no-cache

# Запустить заново
docker-compose up -d
```

---

**Если проблема не решена:**
1. Проверьте логи: `docker-compose logs -f`
2. Проверьте конфигурацию: `.env` и `.env.marzban`
3. Убедитесь, что все порты открыты
4. Проверьте, что DNS правильно настроен


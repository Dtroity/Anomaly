# 🚀 Быстрое развертывание Anomaly Connect

## 📍 Текущая структура проекта

Проект клонируется в `/opt/Anomaly`:

```bash
cd /opt
git clone https://github.com/Dtroity/Anomaly.git
cd Anomaly
```

## ⚡ Быстрый старт (3 шага)

### 1. Настройка DNS

В панели Timeweb Cloud создайте 3 A записи для домена `anomaly-connect.online`:

| Тип | Имя | IP | TTL |
|-----|-----|----|-----|
| A | @ | 72.56.79.212 | 600 |
| A | api | 72.56.79.212 | 600 |
| A | panel | 72.56.79.212 | 600 |

**Подождите 10-30 минут** для распространения DNS.

### 2. Настройка и запуск

```bash
# Перейдите в директорию проекта
cd /opt/Anomaly

# Создайте .env файл (если шаблон отсутствует, используйте CREATE_ENV.sh)
if [ -f "env.before-ssl.template" ]; then
    cp env.before-ssl.template .env
else
    chmod +x CREATE_ENV.sh
    ./CREATE_ENV.sh
fi
nano .env  # Заполните обязательные параметры (BOT_TOKEN, ADMIN_IDS, пароли)

# Создайте .env.marzban
cp env.marzban.template .env.marzban
nano .env.marzban  # Настройте пароль для Marzban

# Запустите сервисы
docker-compose up -d
```

### 3. Получение SSL

```bash
cd /opt/Anomaly
chmod +x setup-ssl.sh
sudo ./setup-ssl.sh
```

После получения SSL обновите `.env`:
```env
APP_URL=https://api.anomaly-connect.online
PANEL_URL=https://panel.anomaly-connect.online
```

И перезапустите:
```bash
docker-compose restart api bot
```

## 📋 Обязательные параметры в .env

```env
# Telegram Bot
BOT_TOKEN=your_bot_token_from_botfather
ADMIN_IDS=your_telegram_id

# Database
DB_PASSWORD=strong_password_here

# Marzban
MARZBAN_PASSWORD=strong_password_here

# Payments (YooKassa)
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key

# API Secret (сгенерируйте случайную строку)
API_SECRET_KEY=$(openssl rand -hex 32)

# ⚠️ ДО получения SSL используйте HTTP:
APP_URL=http://api.anomaly-connect.online
PANEL_URL=http://panel.anomaly-connect.online
```

## ✅ Проверка работы

```bash
# Статус сервисов
cd /opt/Anomaly
docker-compose ps

# Логи
docker-compose logs -f

# Проверка API
curl https://api.anomaly-connect.online/health

# Проверка бота в Telegram
# Отправьте /start вашему боту
```

## 📚 Дополнительная документация

- `QUICK_START.md` - краткая инструкция
- `docs/DEPLOYMENT_STEPS.md` - полная пошаговая инструкция
- `docs/DNS_SETUP.md` - детальная настройка DNS
- `docs/SSL_SETUP.md` - настройка SSL сертификатов

## 🔧 Полезные команды

```bash
# Перезапуск сервисов
docker-compose restart

# Просмотр логов конкретного сервиса
docker-compose logs -f bot
docker-compose logs -f api
docker-compose logs -f nginx

# Остановка всех сервисов
docker-compose down

# Обновление проекта
cd /opt/Anomaly
git pull
docker-compose up -d --build
```

## 🆘 Решение проблем

### DNS не распространяется
- Подождите 30-60 минут
- Проверьте: `nslookup api.anomaly-connect.online`

### SSL не получается
- Убедитесь, что DNS распространился
- Проверьте, что порт 80 открыт: `ufw allow 80/tcp`

### Бот не отвечает
- Проверьте BOT_TOKEN в `.env`
- Проверьте логи: `docker-compose logs bot`

### Сервисы не запускаются
- Проверьте логи: `docker-compose logs`
- Убедитесь, что все параметры в `.env` заполнены

---

**Важно:** Все скрипты автоматически определяют директорию проекта (`/opt/Anomaly`), поэтому их можно запускать из любой директории, если вы находитесь в `/opt/Anomaly`.


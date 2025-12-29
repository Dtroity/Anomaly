# Руководство по развертыванию Anomaly VPN

## 📋 Обзор

Это руководство поможет вам развернуть Anomaly VPN на двух серверах:
- **VPS #1 (Control Plane)**: Telegram-бот, API, база данных
- **VPS #2 (VPN Node)**: Marzban с VLESS Reality

## 🖥️ Требования к серверам

### VPS #1 - Control Plane
- **ОС**: Ubuntu 20.04+ / Debian 11+
- **RAM**: минимум 2 GB
- **Диск**: минимум 20 GB
- **CPU**: 2 ядра
- **Сеть**: домен с SSL (для webhook)

### VPS #2 - VPN Node
- **ОС**: Ubuntu 20.04+ / Debian 11+
- **RAM**: минимум 1 GB
- **Диск**: минимум 10 GB
- **CPU**: 1 ядро
- **Сеть**: публичный IP

## 🚀 Шаг 1: Подготовка VPS #2 (VPN Node)

### 1.1 Установка Marzban

```bash
# Подключитесь к VPS #2
ssh root@your-vpn-node-ip

# Загрузите проект с готовым Marzban
# Убедитесь, что директория Marzban-0.8.4 присутствует в проекте

# Запустите скрипт установки (использует готовый Marzban из директории)
cd /path/to/anomaly-vpn
bash marzban-setup.sh

# Скрипт установит Marzban напрямую на сервер:
# - Установит Xray-core
# - Установит Python зависимости
# - Настроит базу данных
# - Создаст systemd сервис
# - Запустит Marzban
```

### 1.2 Настройка Marzban

1. Откройте панель Marzban: `https://YOUR_VPS_IP:62050`
2. Войдите с учетными данными по умолчанию:
   - Username: `root`
   - Password: `root`
3. **Смените пароль администратора**
4. Настройте VLESS Reality протокол
5. Запишите учетные данные для использования в VPS #1:
   - API URL: `https://YOUR_VPS_IP:62050`
   - Username: `root` (или ваш новый логин)
   - Password: (ваш новый пароль)

### 1.3 Настройка Firewall

```bash
# Разрешить необходимые порты
ufw allow 62050/tcp  # Marzban панель
ufw allow 443/tcp    # VLESS Reality
ufw allow 80/tcp     # HTTP (для Let's Encrypt)
ufw enable
```

## 🚀 Шаг 2: Подготовка VPS #1 (Control Plane)

### 2.1 Клонирование проекта

```bash
# Подключитесь к VPS #1
ssh root@your-control-plane-ip

# Клонируйте репозиторий
git clone <repository-url> /opt/anomaly-vpn
cd /opt/anomaly-vpn

# Или загрузите файлы проекта
```

### 2.2 Установка зависимостей

```bash
# Запустите скрипт установки
bash install.sh

# Скрипт установит напрямую на сервер:
# - PostgreSQL (база данных)
# - Python 3 и виртуальное окружение
# - Nginx (веб-сервер)
# - Certbot (для SSL)
# - Supervisor (для управления процессами)
# - Все необходимые пакеты
# - Создаст systemd сервисы для бота и API
```

### 2.3 Настройка конфигурации

```bash
# Создайте .env файл из шаблона
cp .env.template .env
nano .env
```

**Обязательные параметры для настройки:**

```env
# Telegram Bot
BOT_TOKEN=your_telegram_bot_token_here
ADMIN_IDS=123456789,987654321

# Database
DB_PASSWORD=strong_random_password_here

# Marzban API (VPS #2)
MARZBAN_API_URL=https://your-vpn-node-ip:62050
MARZBAN_USERNAME=root
MARZBAN_PASSWORD=your_marzban_password

# YooKassa
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key
YOOKASSA_TEST_MODE=false  # false для продакшена

# Telegram Payments (опционально)
TELEGRAM_PAYMENT_PROVIDER_TOKEN=your_provider_token

# Application
APP_URL=https://your-domain.com
API_SECRET_KEY=generate_random_secret_key_here
```

### 2.4 Получение Telegram Bot Token

1. Найдите [@BotFather](https://t.me/BotFather) в Telegram
2. Отправьте `/newbot`
3. Следуйте инструкциям для создания бота
4. Скопируйте полученный токен в `.env`

### 2.5 Получение Telegram Admin ID

1. Найдите [@userinfobot](https://t.me/userinfobot) в Telegram
2. Отправьте `/start`
3. Скопируйте ваш ID (число)
4. Добавьте в `ADMIN_IDS` в `.env` (через запятую для нескольких админов)

### 2.6 Настройка YooKassa

1. Зарегистрируйтесь на [yookassa.ru](https://yookassa.ru/)
2. Создайте магазин
3. Получите Shop ID и Secret Key
4. Настройте webhook: `https://your-domain.com/webhook/yookassa`
5. Добавьте данные в `.env`

### 2.7 Настройка Nginx и SSL

```bash
# Создайте конфигурацию Nginx
nano /etc/nginx/sites-available/anomaly
```

**Содержимое файла:**

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# Активируйте конфигурацию
ln -s /etc/nginx/sites-available/anomaly /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Получите SSL сертификат
certbot --nginx -d your-domain.com
```

## 🚀 Шаг 3: Запуск сервисов

### 3.1 Запуск на VPS #1

```bash
cd /opt/anomaly-vpn
bash start.sh

# Или вручную через systemd
systemctl start anomaly-bot
systemctl start anomaly-api
systemctl start postgresql
```

### 3.2 Проверка статуса

```bash
# Проверьте статус сервисов
systemctl status anomaly-bot
systemctl status anomaly-api
systemctl status postgresql

# Проверьте логи
journalctl -u anomaly-bot -f
journalctl -u anomaly-api -f

# Или логи из файлов
tail -f /opt/anomaly-vpn/vpnbot/logs/bot.log
tail -f /opt/anomaly-vpn/vpnbot/logs/api.log
```

### 3.3 Тестирование

1. Отправьте `/start` вашему Telegram боту
2. Проверьте работу команд
3. Проверьте админ-панель: `/admin`
4. Проверьте API: `https://your-domain.com/health`

## 🔧 Шаг 4: Настройка тарифов

Тарифы создаются автоматически при первом запуске. Для изменения:

```bash
# Подключитесь к базе данных
sudo -u postgres psql -d anomaly

# Просмотрите тарифы
SELECT * FROM subscription_plans;

# Обновите тариф (пример)
UPDATE subscription_plans 
SET price = 399.0, traffic_limit_gb = 150 
WHERE id = 1;
```

## 🔒 Шаг 5: Безопасность

### 5.1 Firewall на VPS #1

```bash
# Разрешить только необходимые порты
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw enable
```

### 5.2 Ограничение доступа к Marzban

На VPS #2 ограничьте доступ к панели Marzban:

```bash
# Разрешить доступ только с VPS #1
ufw allow from VPS_1_IP to any port 62050
ufw deny 62050/tcp
```

### 5.3 Резервное копирование

```bash
# Создайте скрипт бэкапа
nano /opt/anomaly-vpn/backup.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/opt/anomaly-vpn/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Бэкап базы данных
sudo -u postgres pg_dump anomaly > $BACKUP_DIR/db_$DATE.sql

# Бэкап .env
cp .env $BACKUP_DIR/env_$DATE.backup

# Удалить старые бэкапы (старше 7 дней)
find $BACKUP_DIR -type f -mtime +7 -delete
```

```bash
chmod +x /opt/anomaly-vpn/backup.sh

# Добавьте в cron (ежедневно в 3:00)
crontab -e
# Добавьте строку:
0 3 * * * /opt/anomaly-vpn/backup.sh
```

## 📊 Шаг 6: Мониторинг

### 6.1 Проверка логов

```bash
# Все сервисы
journalctl -u anomaly-bot -f
journalctl -u anomaly-api -f

# Только бот
journalctl -u anomaly-bot -f

# Только API
journalctl -u anomaly-api -f

# База данных
journalctl -u postgresql -f
```

### 6.2 Метрики через бота

- `/admin` - панель администратора
- `/stats` - статистика
- `/users` - список пользователей

## 🔄 Обновление

```bash
cd /opt/anomaly-vpn

# Сделайте бэкап
./backup.sh

# Обновите код
git pull

# Обновите зависимости Python
cd vpnbot
source venv/bin/activate
pip install -r requirements.txt --upgrade

# Перезапустите сервисы
systemctl restart anomaly-bot anomaly-api
```

## 🆘 Устранение неполадок

### Бот не отвечает

1. Проверьте токен в `.env`
2. Проверьте статус: `systemctl status anomaly-bot`
3. Проверьте логи: `journalctl -u anomaly-bot -f`
4. Перезапустите: `systemctl restart anomaly-bot`

### Ошибки подключения к Marzban

1. Проверьте доступность: `curl -k https://vps2-ip:62050/api/system`
2. Проверьте учетные данные в `.env`
3. Проверьте firewall на VPS #2

### Проблемы с платежами

1. Проверьте webhook URL в настройках ЮKassa
2. Проверьте логи API: `journalctl -u anomaly-api -f | grep webhook`
3. Убедитесь, что `APP_URL` правильный
4. Проверьте доступность API: `curl https://your-domain.com/health`

### Проблемы с базой данных

1. Проверьте статус: `systemctl status postgresql`
2. Проверьте подключение: `sudo -u postgres psql -d anomaly -c "SELECT 1;"`
3. Проверьте настройки в `.env` (DB_HOST=localhost, DB_PORT=5432)
4. Восстановите из бэкапа при необходимости

## 📞 Поддержка

При возникновении проблем:
1. Проверьте логи
2. Проверьте документацию
3. Создайте issue в репозитории

---

**Важно**: Регулярно делайте резервные копии и обновляйте систему!


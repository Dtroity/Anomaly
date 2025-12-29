# Прямая установка Anomaly VPN (без Docker)

## 📋 Обзор

Этот документ описывает установку Anomaly VPN **напрямую на VPS** без использования Docker. Все компоненты устанавливаются как системные сервисы через systemd.

## 🏗️ Архитектура установки

### VPS #1 (Control Plane)
- **Telegram Bot** - systemd сервис `anomaly-bot`
- **FastAPI** - systemd сервис `anomaly-api`
- **PostgreSQL** - системный сервис
- **Nginx** - веб-сервер для проксирования API

### VPS #2 (VPN Node)
- **Marzban** - systemd сервис `marzban`
- **Xray-core** - системная установка
- **SQLite/PostgreSQL** - база данных Marzban

## 🚀 Быстрая установка

### VPS #2: Установка Marzban

```bash
# 1. Загрузите проект на сервер
cd /opt
git clone <repository-url> anomaly-vpn
cd anomaly-vpn

# 2. Запустите установку Marzban
sudo bash marzban-setup.sh

# 3. Настройте .env файл Marzban
sudo nano /opt/marzban/.env

# 4. Перезапустите Marzban
sudo systemctl restart marzban
```

### VPS #1: Установка бота и API

```bash
# 1. Загрузите проект на сервер
cd /opt
git clone <repository-url> anomaly-vpn
cd anomaly-vpn

# 2. Настройте .env файл
cp .env.template .env
sudo nano .env

# 3. Запустите установку
sudo bash install.sh

# 4. Проверьте статус
sudo systemctl status anomaly-bot
sudo systemctl status anomaly-api
```

## 📁 Структура установки

### VPS #1
```
/opt/anomaly-vpn/
├── vpnbot/
│   ├── venv/              # Виртуальное окружение Python
│   ├── data/             # Данные приложения
│   ├── logs/             # Логи
│   └── [исходный код]
├── .env                   # Конфигурация
└── [другие файлы]

/etc/systemd/system/
├── anomaly-bot.service    # Сервис бота
└── anomaly-api.service    # Сервис API

/var/lib/postgresql/       # База данных PostgreSQL
```

### VPS #2
```
/opt/marzban/
├── venv/                  # Виртуальное окружение Python
├── .env                   # Конфигурация Marzban
└── [исходный код Marzban]

/var/lib/marzban/
├── db.sqlite3             # База данных (если SQLite)
└── xray_config.json        # Конфигурация Xray

/etc/systemd/system/
└── marzban.service        # Сервис Marzban
```

## ⚙️ Управление сервисами

### Бот и API (VPS #1)

```bash
# Статус
systemctl status anomaly-bot
systemctl status anomaly-api

# Запуск
systemctl start anomaly-bot
systemctl start anomaly-api

# Остановка
systemctl stop anomaly-bot
systemctl stop anomaly-api

# Перезапуск
systemctl restart anomaly-bot
systemctl restart anomaly-api

# Автозапуск при загрузке
systemctl enable anomaly-bot
systemctl enable anomaly-api

# Логи
journalctl -u anomaly-bot -f
journalctl -u anomaly-api -f
```

### Marzban (VPS #2)

```bash
# Статус
systemctl status marzban

# Запуск
systemctl start marzban

# Остановка
systemctl stop marzban

# Перезапуск
systemctl restart marzban

# Автозапуск
systemctl enable marzban

# Логи
journalctl -u marzban -f
```

## 🔧 Конфигурация

### Настройка бота (VPS #1)

```bash
# Редактировать конфигурацию
sudo nano /opt/anomaly-vpn/.env

# После изменений перезапустить
sudo systemctl restart anomaly-bot anomaly-api
```

### Настройка Marzban (VPS #2)

```bash
# Редактировать конфигурацию
sudo nano /opt/marzban/.env

# После изменений перезапустить
sudo systemctl restart marzban
```

## 📊 Мониторинг

### Проверка работы бота

```bash
# Логи в реальном времени
journalctl -u anomaly-bot -f

# Последние 100 строк
journalctl -u anomaly-bot -n 100

# Логи за сегодня
journalctl -u anomaly-bot --since today
```

### Проверка работы API

```bash
# Проверка доступности
curl http://localhost:8000/health

# Логи
journalctl -u anomaly-api -f
```

### Проверка работы Marzban

```bash
# Проверка API
curl -k https://localhost:62050/api/system

# Логи
journalctl -u marzban -f
```

## 🔄 Обновление

### Обновление бота и API

```bash
cd /opt/anomaly-vpn

# Обновить код
git pull

# Обновить зависимости
cd vpnbot
source venv/bin/activate
pip install -r requirements.txt --upgrade

# Перезапустить
systemctl restart anomaly-bot anomaly-api
```

### Обновление Marzban

```bash
cd /opt/marzban

# Обновить код (если используете git)
git pull

# Обновить зависимости
source venv/bin/activate
pip install -r requirements.txt --upgrade

# Применить миграции БД
alembic upgrade head

# Перезапустить
systemctl restart marzban
```

## 🗄️ База данных

### PostgreSQL (VPS #1)

```bash
# Подключение к БД
sudo -u postgres psql -d anomaly

# Бэкап
sudo -u postgres pg_dump anomaly > backup_$(date +%Y%m%d).sql

# Восстановление
sudo -u postgres psql anomaly < backup_20240101.sql
```

### SQLite (Marzban на VPS #2)

```bash
# Бэкап
cp /var/lib/marzban/db.sqlite3 backup_$(date +%Y%m%d).sqlite3

# Восстановление
cp backup_20240101.sqlite3 /var/lib/marzban/db.sqlite3
systemctl restart marzban
```

## 🆘 Устранение неполадок

### Бот не запускается

```bash
# Проверить статус
systemctl status anomaly-bot

# Проверить логи
journalctl -u anomaly-bot -n 50

# Проверить .env файл
cat /opt/anomaly-vpn/.env

# Проверить виртуальное окружение
ls -la /opt/anomaly-vpn/vpnbot/venv/bin/python
```

### API не отвечает

```bash
# Проверить статус
systemctl status anomaly-api

# Проверить порт
netstat -tlnp | grep 8000

# Проверить Nginx
systemctl status nginx
nginx -t
```

### Marzban не работает

```bash
# Проверить статус
systemctl status marzban

# Проверить Xray
which xray
xray version

# Проверить конфигурацию
marzban cli system status
```

## 🔒 Безопасность

### Ограничение доступа

```bash
# Firewall для VPS #1
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw enable

# Firewall для VPS #2
ufw allow 22/tcp      # SSH
ufw allow 62050/tcp   # Marzban (только с VPS #1)
ufw allow 443/tcp     # VLESS Reality
ufw enable
```

### SSL сертификаты

```bash
# Для VPS #1 (API)
certbot --nginx -d your-domain.com

# Для VPS #2 (Marzban)
# Настройте в /opt/marzban/.env
# UVICORN_SSL_CERTFILE=/path/to/cert.pem
# UVICORN_SSL_KEYFILE=/path/to/key.pem
```

## 📝 Логи

### Расположение логов

**VPS #1:**
- Бот: `journalctl -u anomaly-bot` или `/opt/anomaly-vpn/vpnbot/logs/bot.log`
- API: `journalctl -u anomaly-api` или `/opt/anomaly-vpn/vpnbot/logs/api.log`
- PostgreSQL: `/var/log/postgresql/`

**VPS #2:**
- Marzban: `journalctl -u marzban`
- Xray: `/var/log/xray/`

### Ротация логов

Логи systemd автоматически ротируются. Для файловых логов настройте logrotate:

```bash
# Создать конфигурацию
sudo nano /etc/logrotate.d/anomaly-vpn
```

```
/opt/anomaly-vpn/vpnbot/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

---

**Преимущества прямой установки:**
- ✅ Полный контроль над процессами
- ✅ Прямой доступ к логам
- ✅ Легче отладка
- ✅ Меньше накладных расходов
- ✅ Проще интеграция с системными сервисами


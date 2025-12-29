# Anomaly Connect

Коммерческий сервис предоставления сетевого доступа через Telegram-бот.

🌍 **Домен:** `anomaly-connect.online`  
📍 **Control Server:** `72.56.79.212`

## 🎯 Особенности

- 🤖 **Telegram-бот** для управления подписками
- 💳 **Интеграция платежей**: ЮKassa и Telegram Payments
- 🔐 **VLESS Reality** через Marzban
- 🌍 **Мульти-ноды** с автоматическим выбором наименее нагруженной
- 📊 **Аналитика** и статистика
- 🎁 **Промо-коды** и бесплатные подписки
- 🔒 **Безопасность**: Marzban API недоступен извне

## 🏗️ Архитектура

### VPS #1 - Control Server (72.56.79.212)

**Единственный публичный сервер.** Содержит:

- **Marzban** (Docker) - панель управления нодами
- **Telegram Bot** (Docker) - интерфейс для пользователей
- **FastAPI Backend** (Docker) - API и бизнес-логика
- **PostgreSQL** (Docker) - база данных
- **Nginx** (Docker) - обратный прокси + SSL

### VPS #2 - Node (Worker)

**Рабочая нода.** Содержит:

- **Marzban Node** (Docker) - подключается к Control Server
- **Xray Core** - обрабатывает VPN соединения

## 📋 Требования

### VPS #1 - Control Server
- Ubuntu 20.04+ / Debian 11+
- 2 GB RAM минимум
- 20 GB диска
- Docker и Docker Compose
- Домен (для SSL)

### VPS #2 - Node
- Ubuntu 20.04+ / Debian 11+
- 1 GB RAM минимум
- 10 GB диска
- Docker и Docker Compose
- Публичный IP

## 🚀 Быстрый старт

### 1. Установка на VPS #1 (Control Server)

```bash
# Клонировать репозиторий
git clone <repository-url>
cd anomaly-vpn

# Запустить установку Control Server
sudo bash install-control.sh

# Настроить конфигурацию
nano .env
nano .env.marzban
```

### 2. Установка на VPS #2 (Node)

```bash
# Клонировать репозиторий
git clone <repository-url>
cd anomaly-vpn

# Запустить установку Node
sudo bash install-node.sh

# Настроить .env.node
nano .env.node
```

### 3. Настройка DNS

Настройте DNS записи для домена `anomaly-connect.online`:

```
A     api                 72.56.79.212
A     panel               72.56.79.212
A     @                   72.56.79.212
```

### 4. Настройка SSL

```bash
# После настройки DNS
sudo bash setup-ssl.sh
```

### 5. Конфигурация

Отредактируйте `.env` файл на VPS #1:

```env
# Application
APP_URL=https://api.anomaly-connect.online
PANEL_URL=https://panel.anomaly-connect.online

# Telegram Bot
BOT_TOKEN=your_telegram_bot_token
ADMIN_IDS=123456789,987654321

# Marzban API (локально на Control Server)
MARZBAN_API_URL=http://marzban:62050
MARZBAN_USERNAME=root
MARZBAN_PASSWORD=your_marzban_password

# YooKassa
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key
```

### 6. Запуск

```bash
# На VPS #1 (Control Server)
cd /opt/anomaly-vpn
docker-compose up -d

# Проверить статус
docker-compose ps

# Просмотр логов
docker-compose logs -f

# На VPS #2 (Node)
cd /opt/anomaly-node
docker-compose up -d
```

## 📁 Структура проекта

```
anomaly-vpn/
├── docker-compose.yml          # Control Server
├── docker-compose.node.yml     # Node
├── .env.template               # Шаблон конфигурации бота
├── env.marzban.template        # Шаблон конфигурации Marzban
├── env.node.template           # Шаблон конфигурации Node
├── install-control.sh          # Установка Control Server
├── install-node.sh             # Установка Node
├── setup-ssl.sh                # Настройка SSL сертификатов
├── nginx/                      # Конфигурация Nginx
│   ├── nginx.conf
│   └── conf.d/
│       ├── default.conf        # API (api.anomaly-connect.online)
│       ├── panel.conf         # Panel (panel.anomaly-connect.online)
│       └── main.conf          # Landing (anomaly-connect.online)
├── vpnbot/                     # Код бота и API
│   ├── main.py
│   ├── api.py
│   ├── services/
│   └── handlers/
└── docs/                       # Документация
```

## 🤖 Команды бота

### Для пользователей

- `/start` - Главное меню
- `/buy` - Купить подписку
- `/status` - Статус подписки
- `/help` - Справка

### Для администраторов

- `/admin` - Панель администратора
- `/grant <id> <days> <traffic>` - Выдать бесплатный доступ
- `/revoke <id>` - Заблокировать пользователя
- `/stats` - Статистика
- `/broadcast` - Рассылка сообщений

## 💳 Платежи

### ЮKassa

1. Зарегистрируйтесь на [ЮKassa](https://yookassa.ru/)
2. Получите Shop ID и Secret Key
3. Настройте webhook: `https://your-domain.com/webhook/yookassa`
4. Добавьте данные в `.env`

### Telegram Payments

1. Создайте бота через [@BotFather](https://t.me/BotFather)
2. Настройте платежи через [@BotFather](https://t.me/BotFather)
3. Получите Provider Token
4. Добавьте в `.env`: `TELEGRAM_PAYMENT_PROVIDER_TOKEN`

## 🔧 Управление

### Просмотр логов

```bash
# На Control Server
docker-compose logs -f bot      # Логи бота
docker-compose logs -f api      # Логи API
docker-compose logs -f marzban  # Логи Marzban
docker-compose logs -f nginx    # Логи Nginx

# На Node
docker-compose logs -f marzban-node
```

### Перезапуск

```bash
# Control Server
docker-compose restart bot
docker-compose restart api

# Node
docker-compose restart
```

### Остановка

```bash
# Control Server
docker-compose down

# Node
docker-compose down
```

### Обновление

```bash
# Control Server
cd /opt/anomaly-vpn
git pull
docker-compose build
docker-compose up -d

# Node
cd /opt/anomaly-node
git pull
docker-compose build
docker-compose up -d
```

## 🔒 Безопасность

- ✅ Marzban API недоступен извне (только локально)
- ✅ Все внутренние сервисы в Docker network
- ✅ SSL/TLS для всех публичных соединений
- ✅ Firewall ограничивает доступ
- ✅ Используйте сильные пароли
- ✅ Регулярно обновляйте систему

## 📊 Мониторинг

- Логи: `docker-compose logs -f`
- База данных: PostgreSQL в Docker
- Метрики: через `/admin` в боте
- Панель Marzban: `https://panel.anomaly-connect.online` (только для админов, через VPN/IP whitelist)
- API: `https://api.anomaly-connect.online`

## 🆘 Поддержка

- Документация: `docs/`
- Архитектура: `ARCHITECTURE_FINAL.md`
- Развертывание: `DEPLOYMENT.md`
- Админ-гайд: `docs/ADMIN.md`
- Гайд для клиентов: `docs/CLIENTS.md`

## 📝 Лицензия

Проект создан для внутреннего использования.

## ⚠️ Важные замечания

1. **Юридические требования РФ**: Тексты нейтральные, без упоминания "VPN", "обход блокировок"
2. **Безопасность**: Не публикуйте `.env` файлы и токены
3. **Резервное копирование**: Регулярно делайте бэкапы базы данных
4. **Мониторинг**: Следите за использованием ресурсов и трафиком

## 🔄 Обновления

Следите за обновлениями в репозитории. Перед обновлением:
1. Сделайте бэкап базы данных
2. Остановите сервисы
3. Обновите код
4. Запустите миграции (если есть)
5. Запустите сервисы

---

**Anomaly Connect** - Коммерческий сервис сетевого доступа

🌍 **anomaly-connect.online**

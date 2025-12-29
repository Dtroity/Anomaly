# 🏗️ Финальная архитектура Anomaly Connect

## 🌍 Домены и маршруты

| Назначение          | Домен                                  | Доступ                    |
| ------------------- | -------------------------------------- | ------------------------- |
| API / Webhook       | `https://api.anomaly-connect.online`   | Публичный                 |
| Админка (Marzban)   | `https://panel.anomaly-connect.online` | Через VPN / IP Whitelist  |
| Лендинг (будущее)   | `https://anomaly-connect.online`       | Публичный                 |

## 🖥️ VPS #1 — Control Server

**IP:** `72.56.79.212`  
**Домен:** `anomaly-connect.online`  
**Единственная публичная точка входа**

### Компоненты (Docker)

```
┌─────────────────────────────────────────┐
│  Control Server (72.56.79.212)         │
│                                         │
│  ┌──────────┐  ┌──────────┐           │
│  │Telegram  │  │ FastAPI  │           │
│  │   Bot    │  │ Backend  │           │
│  └──────────┘  └──────────┘           │
│                                         │
│  ┌──────────┐  ┌──────────┐           │
│  │ Marzban  │  │PostgreSQL│           │
│  │(Control) │  │   DB     │           │
│  └──────────┘  └──────────┘           │
│                                         │
│  ┌──────────┐                         │
│  │  Nginx   │                         │
│  │ + SSL    │                         │
│  └──────────┘                         │
└─────────────────────────────────────────┘
```

### Контейнеры

1. **api** - FastAPI Backend
   - REST API для бота
   - Webhook обработка платежей
   - Бизнес-логика

2. **bot** - Telegram Bot
   - Интерфейс для пользователей
   - Обработка команд
   - Выдача конфигураций

3. **marzban** - Marzban Control Plane
   - Управление нодами
   - Управление пользователями
   - API доступен только локально (`http://marzban:62050`)

4. **postgres** - PostgreSQL Database
   - Пользователи
   - Платежи
   - Тарифы
   - Промо-коды

5. **nginx** - Reverse Proxy
   - SSL/TLS терминация
   - Маршрутизация запросов
   - Защита внутренних сервисов

### Порты

- `80` - HTTP (редирект на HTTPS)
- `443` - HTTPS (публичный доступ)
- `62050` - Marzban API (только локально, через Docker network)
- `8000` - FastAPI (только локально, через Docker network)

## 🖥️ VPS #2+ — Node (Worker)

**Без домена**  
**Только IP**  
**Может быть сколько угодно**

### Компоненты (Docker)

```
┌─────────────────────────────┐
│  Node Server (IP only)      │
│                             │
│  ┌──────────┐              │
│  │ Marzban  │              │
│  │  Node    │              │
│  └──────────┘              │
│         ↓                   │
│  ┌──────────┐              │
│  │  Xray    │              │
│  │  Core    │              │
│  └──────────┘              │
└─────────────────────────────┘
```

### Контейнеры

1. **marzban-node** - Marzban Node
   - Подключается к Control Server
   - Получает конфигурации
   - Управляет Xray

2. **xray-core** - Xray Core
   - Обрабатывает VPN соединения
   - VLESS Reality протокол
   - Статистика трафика

### Порты

- `443` - VLESS Reality (публичный)
- `80` - HTTP Fallback (публичный)
- `22` - SSH (для управления)

## 🔄 Поток данных

### Регистрация пользователя

```
User
  ↓ Telegram
Bot (api.anomaly-connect.online)
  ↓
FastAPI Backend
  ↓
Marzban API (локально: http://marzban:62050)
  ↓
Создание пользователя
  ↓
Выбор наименее загруженной ноды
  ↓
Генерация конфигурации
  ↓
Возврат в Bot → User
```

### Подключение клиента

```
Client
  ↓ VLESS Reality
Node:443
  ↓
Xray Core
  ↓
Интернет
```

### Управление нодой

```
Control Server
  ↓
Marzban API
  ↓ Push конфигурации
Node
  ↓
Обновление Xray
```

## 🔐 Безопасность

### Control Server

1. **Marzban API**
   - Доступен только внутри Docker network
   - Не экспортируется наружу
   - Защищен аутентификацией

2. **Nginx**
   - SSL/TLS для всех соединений
   - Rate limiting
   - Security headers
   - IP whitelist для панели

3. **Firewall**
   ```bash
   ufw allow 22/tcp    # SSH
   ufw allow 80/tcp    # HTTP
   ufw allow 443/tcp   # HTTPS
   ufw deny 62050/tcp  # Marzban (только локально)
   ufw deny 8000/tcp   # API (только локально)
   ufw enable
   ```

### Node

1. **Нет публичного API**
   - Node не принимает управляющие соединения
   - Все управление через Control Server

2. **Firewall**
   ```bash
   ufw allow 22/tcp    # SSH
   ufw allow 443/tcp   # VLESS Reality
   ufw allow 80/tcp    # HTTP Fallback
   ufw enable
   ```

## 📊 Структура проекта

### Control Server

```
/opt/anomaly-vpn/
├── docker-compose.yml
├── .env
├── .env.marzban
├── nginx/
│   ├── nginx.conf
│   └── conf.d/
│       ├── default.conf    # API (api.anomaly-connect.online)
│       ├── panel.conf      # Panel (panel.anomaly-connect.online)
│       └── main.conf       # Landing (anomaly-connect.online)
├── vpnbot/
│   ├── main.py
│   ├── api.py
│   ├── services/
│   └── handlers/
└── logs/
```

### Node

```
/opt/anomaly-node/
├── docker-compose.yml
├── .env.node
└── logs/
```

## 🌐 DNS настройки

Для домена `anomaly-connect.online`:

```
A     @                   72.56.79.212
A     api                 72.56.79.212
A     panel               72.56.79.212
CNAME www                 @
```

## 🔧 Переменные окружения

### Control Server `.env`

```env
# Основное
APP_NAME=Anomaly Connect
APP_URL=https://api.anomaly-connect.online
PANEL_URL=https://panel.anomaly-connect.online
API_SECRET_KEY=generate_random_secret_key_here

# Telegram
BOT_TOKEN=your_telegram_bot_token
ADMIN_IDS=123456789,987654321

# Marzban (локальный)
MARZBAN_API_URL=http://marzban:62050
MARZBAN_USERNAME=root
MARZBAN_PASSWORD=your_marzban_password

# Платежи
YOOKASSA_SHOP_ID=your_shop_id
YOOKASSA_SECRET_KEY=your_secret_key
TELEGRAM_PAYMENT_PROVIDER_TOKEN=your_provider_token

# Database
DB_NAME=anomaly
DB_USER=anomaly
DB_PASSWORD=strong_password
DB_HOST=db
DB_PORT=5432
```

### Node `.env.node`

```env
# Control Server Connection
CONTROL_SERVER_URL=https://api.anomaly-connect.online
CONTROL_SERVER_IP=72.56.79.212
CONTROL_SERVER_PORT=62050
CONTROL_SERVER_USERNAME=root
CONTROL_SERVER_PASSWORD=your_marzban_password

# Node Settings
NODE_ID=node-eu-1
NODE_NAME=EU Node 1
NODE_REGION=EU
```

## 📈 Масштабирование

### Добавление новой ноды

1. Установите Node на новый VPS
2. Настройте `.env.node` с уникальным `NODE_ID`
3. Зарегистрируйте ноду в Marzban на Control Server
4. Node автоматически получит конфигурации

### Балансировка нагрузки

- Marzban автоматически распределяет пользователей по нодам
- Можно настроить приоритеты нод
- Автоматический failover при недоступности ноды

## 🔄 Обновление

### Control Server

```bash
cd /opt/anomaly-vpn
git pull
docker-compose build
docker-compose up -d
```

### Node

```bash
cd /opt/anomaly-node
git pull
docker-compose build
docker-compose up -d
```

---

**Anomaly Connect** - Коммерческий сервис сетевого доступа


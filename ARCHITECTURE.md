# 🏗️ Архитектура Anomaly VPN

## 📐 Общая схема

```
┌─────────────────────────────────────────────────────────┐
│              VPS #1 - Control Server                    │
│              IP: 72.56.79.212                          │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │Telegram  │  │ FastAPI  │  │ Marzban  │            │
│  │   Bot    │→ │ Backend  │→ │  Panel   │            │
│  └──────────┘  └──────────┘  └──────────┘            │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │  Nginx   │  │PostgreSQL│  │  Logs    │            │
│  │  + SSL   │  │   DB     │  │          │            │
│  └──────────┘  └──────────┘  └──────────┘            │
└─────────────────────────────────────────────────────────┘
                        ↓
              [Управление нодами]
                        ↓
┌─────────────────────────────────────────────────────────┐
│              VPS #2 - Node (Worker)                     │
│                                                         │
│  ┌──────────┐  ┌──────────┐                            │
│  │ Marzban  │  │  Xray    │                            │
│  │  Node    │→ │  Core    │                            │
│  └──────────┘  └──────────┘                            │
│                                                         │
│  Порт 443: VLESS Reality                                │
│  Порт 80:  HTTP Fallback                                │
└─────────────────────────────────────────────────────────┘
```

## 🔹 VPS #1 - Control Server

### Компоненты

1. **Marzban** (Docker)
   - Панель управления нодами
   - API доступен только локально (`localhost:62050`)
   - Управление пользователями и конфигурациями

2. **Telegram Bot** (Docker)
   - Интерфейс для пользователей
   - Обработка команд и платежей
   - Выдача конфигураций

3. **FastAPI Backend** (Docker)
   - REST API для бота
   - Обработка webhook'ов платежей
   - Бизнес-логика

4. **PostgreSQL** (Docker)
   - База данных пользователей
   - История платежей
   - Тарифы и промо-коды

5. **Nginx** (Docker)
   - Обратный прокси
   - SSL/TLS терминация
   - Маршрутизация запросов

### Сетевые порты

- `80` - HTTP (редирект на HTTPS)
- `443` - HTTPS (публичный доступ)
- `62050` - Marzban API (только локально, через Docker network)
- `8000` - FastAPI (только локально, через Docker network)

### Безопасность

- ✅ Marzban API недоступен извне
- ✅ Все внутренние сервисы в Docker network
- ✅ Публичный доступ только через Nginx с SSL
- ✅ Firewall ограничивает входящие соединения

## 🔹 VPS #2 - Node

### Компоненты

1. **Marzban Node** (Docker)
   - Подключается к Control Server
   - Получает конфигурации
   - Управляет Xray

2. **Xray Core**
   - Обрабатывает VPN соединения
   - VLESS Reality протокол
   - Статистика трафика

### Сетевые порты

- `443` - VLESS Reality (публичный)
- `80` - HTTP Fallback (публичный)
- `22` - SSH (для управления)

### Безопасность

- ✅ Нет публичного API
- ✅ Подключение к Control Server инициативное (outbound)
- ✅ Firewall разрешает только необходимые порты

## 🔄 Поток данных

### Регистрация пользователя

```
User → Telegram Bot → FastAPI → PostgreSQL
                              → Marzban API (локально)
                              → Создание пользователя
                              → Генерация конфигурации
                              → Возврат в Bot → User
```

### Получение конфигурации

```
User → Telegram Bot → FastAPI → Marzban API
                              → Получение subscription URL
                              → Возврат в Bot → User
```

### Подключение клиента

```
Client → Node:443 (VLESS Reality)
      → Xray Core
      → Интернет
```

### Управление нодой

```
Control Server → Marzban API
              → Push конфигурации в Node
              → Node обновляет Xray
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

3. **Firewall**
   ```bash
   ufw allow 22/tcp    # SSH
   ufw allow 80/tcp    # HTTP
   ufw allow 443/tcp   # HTTPS
   ufw deny 62050/tcp  # Marzban (только локально)
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

## 📊 Масштабирование

### Добавление новой ноды

1. Установите Node на новый VPS
2. Настройте `.env.node` с уникальным `NODE_ID`
3. Зарегистрируйте ноду в Marzban на Control Server
4. Node автоматически получит конфигурации

### Балансировка нагрузки

- Marzban автоматически распределяет пользователей по нодам
- Можно настроить приоритеты нод
- Автоматический failover при недоступности ноды

## 🗄️ База данных

### Control Server

- **PostgreSQL** - основная БД
  - Пользователи
  - Платежи
  - Тарифы
  - Промо-коды

- **Marzban** - использует ту же PostgreSQL
  - Конфигурации пользователей
  - Статистика трафика
  - Настройки нод

### Node

- **SQLite** (локально)
  - Кэш конфигураций
  - Локальная статистика

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

## 📝 Логи

### Control Server

- Бот: `docker-compose logs -f bot`
- API: `docker-compose logs -f api`
- Marzban: `docker-compose logs -f marzban`
- Nginx: `docker-compose logs -f nginx`

### Node

- Node: `docker-compose logs -f marzban-node`
- Xray: логи в контейнере

---

**Архитектура обеспечивает:**
- ✅ Безопасность (API недоступен извне)
- ✅ Масштабируемость (легко добавлять ноды)
- ✅ Надежность (изоляция компонентов)
- ✅ Производительность (оптимальное распределение нагрузки)


# ⚡ Быстрый старт - Anomaly Connect

## 🎯 Краткая инструкция

### 1️⃣ Настройка DNS (СНАЧАЛА!)

В панели Timeweb Cloud создайте 3 A записи:

| Тип | Имя | IP | TTL |
|-----|-----|----|-----|
| A | @ | 72.56.79.212 | 600 |
| A | api | 72.56.79.212 | 600 |
| A | panel | 72.56.79.212 | 600 |

**Подождите 10-30 минут** для распространения DNS.

📖 **Подробнее:** `docs/DNS_SETUP.md`

### 2️⃣ Настройка .env (ДО SSL!)

```bash
# Перейдите в директорию проекта
cd /opt/Anomaly

# Скопируйте шаблон
cp env.before-ssl.template .env

# Отредактируйте
nano .env
```

**Обязательно используйте HTTP:**
```env
APP_URL=http://api.anomaly-connect.online
PANEL_URL=http://panel.anomaly-connect.online
```

📖 **Подробнее:** см. `env.before-ssl.template`

### 3️⃣ Запуск сервисов

```bash
cd /opt/Anomaly
docker-compose up -d
```

### 4️⃣ Получение SSL (ПОСЛЕ DNS!)

```bash
cd /opt/Anomaly
chmod +x setup-ssl.sh
sudo ./setup-ssl.sh
```

### 5️⃣ Обновление .env (ПОСЛЕ SSL!)

Измените на HTTPS:
```env
APP_URL=https://api.anomaly-connect.online
PANEL_URL=https://panel.anomaly-connect.online
```

Перезапустите:
```bash
cd /opt/Anomaly
docker-compose restart api bot
```

## ✅ Проверка

```bash
# Проверка DNS
nslookup api.anomaly-connect.online

# Проверка HTTP (до SSL)
curl http://api.anomaly-connect.online

# Проверка HTTPS (после SSL)
curl https://api.anomaly-connect.online

# Проверка статуса сервисов
cd /opt/Anomaly
docker-compose ps
docker-compose logs -f
```

## 📚 Дополнительная документация

- `docs/DNS_SETUP.md` - детальная настройка DNS
- `docs/SSL_SETUP.md` - настройка SSL сертификатов
- `docs/DEPLOYMENT_STEPS.md` - полная пошаговая инструкция

---

**Важно:** Следуйте порядку: DNS → .env (HTTP) → Запуск → SSL → .env (HTTPS)

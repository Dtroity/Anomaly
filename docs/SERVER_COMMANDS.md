# 🖥️ Команды для выполнения на сервере

## 📥 Обновление репозитория

```bash
cd /opt/Anomaly
git pull
```

## 📝 Создание .env файла

### Вариант 1: Использовать скрипт (рекомендуется)

```bash
cd /opt/Anomaly
chmod +x CREATE_ENV.sh
./CREATE_ENV.sh
nano .env
```

### Вариант 2: Копировать из шаблона (если файл есть)

```bash
cd /opt/Anomaly
cp env.before-ssl.template .env
nano .env
```

## ⚙️ Настройка .env файла

```bash
cd /opt/Anomaly
nano .env
```

**Обязательно заполните:**

1. **BOT_TOKEN** - получите у @BotFather в Telegram
   ```bash
   # Пример: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
   ```

2. **ADMIN_IDS** - ваш Telegram ID (можно узнать у @userinfobot)
   ```bash
   # Пример: 123456789
   # Для нескольких админов: 123456789,987654321
   ```

3. **DB_PASSWORD** - надежный пароль для PostgreSQL
   ```bash
   # Сгенерируйте: openssl rand -base64 32
   ```

4. **MARZBAN_PASSWORD** - надежный пароль для Marzban
   ```bash
   # Сгенерируйте: openssl rand -base64 32
   ```

5. **API_SECRET_KEY** - секретный ключ для API
   ```bash
   # Сгенерируйте: openssl rand -hex 32
   ```

6. **YOOKASSA_SHOP_ID** и **YOOKASSA_SECRET_KEY** - из личного кабинета ЮKassa
   ```bash
   # Получите на https://yookassa.ru/my
   ```

## 🔧 Настройка .env.marzban

```bash
cd /opt/Anomaly
cp env.marzban.template .env.marzban
nano .env.marzban
```

**Важно:** Используйте тот же `DB_PASSWORD`, что и в `.env`:
```env
DATABASE_URL=postgresql://anomaly:ВАШ_DB_PASSWORD@db:5432/marzban
SUDO_PASSWORD=ВАШ_MARZBAN_PASSWORD
```

## 🚀 Первый запуск сервисов

```bash
cd /opt/Anomaly

# Запустить все сервисы
docker-compose up -d

# Проверить статус
docker-compose ps

# Просмотреть логи
docker-compose logs -f
```

## 🔐 Получение SSL сертификата

**ВАЖНО:** Делайте это только после того, как DNS распространился (проверьте: `nslookup api.anomaly-connect.online`)

```bash
cd /opt/Anomaly

# Открыть порты
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Запустить скрипт настройки SSL
chmod +x setup-ssl.sh
sudo ./setup-ssl.sh
```

## 🔄 Обновление .env после получения SSL

```bash
cd /opt/Anomaly
nano .env
```

Измените:
```env
APP_URL=https://api.anomaly-connect.online
PANEL_URL=https://panel.anomaly-connect.online
```

Перезапустите сервисы:
```bash
docker-compose restart api bot
```

## ✅ Проверка работы

```bash
# Проверка статуса всех сервисов
docker-compose ps

# Проверка API
curl http://api.anomaly-connect.online
curl https://api.anomaly-connect.online

# Проверка логов
docker-compose logs -f bot
docker-compose logs -f api
docker-compose logs -f nginx

# Проверка базы данных
docker-compose exec db psql -U anomaly -d anomaly -c "SELECT version();"
```

## 📊 Полезные команды

```bash
# Перезапуск всех сервисов
docker-compose restart

# Перезапуск конкретного сервиса
docker-compose restart bot
docker-compose restart api
docker-compose restart nginx

# Просмотр логов конкретного сервиса
docker-compose logs -f bot
docker-compose logs -f api
docker-compose logs -f db
docker-compose logs -f marzban
docker-compose logs -f nginx

# Остановка всех сервисов
docker-compose down

# Запуск с пересборкой
docker-compose up -d --build

# Просмотр использования ресурсов
docker stats
```

## 🔧 Настройка автоматических задач

```bash
cd /opt/Anomaly
chmod +x setup-cron.sh
sudo ./setup-cron.sh
```

## 📦 Ручной бэкап

```bash
cd /opt/Anomaly
chmod +x backup.sh
./backup.sh
```

## 🆘 Если что-то пошло не так

```bash
# Просмотр всех логов
docker-compose logs

# Проверка конфигурации Nginx
docker-compose exec nginx nginx -t

# Пересборка всех контейнеров
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Полный сброс (ОСТОРОЖНО: удалит данные!)
docker-compose down -v
docker-compose up -d --build
```

## 📚 Дополнительная документация

- `README_DEPLOY.md` - быстрая инструкция по развертыванию
- `docs/DEPLOYMENT_STEPS.md` - полная пошаговая инструкция
- `docs/DNS_SETUP.md` - детальная настройка DNS
- `docs/SSL_SETUP.md` - настройка SSL сертификатов
- `docs/TROUBLESHOOTING.md` - решение проблем

---

**Порядок действий на сервере:**

1. ✅ `cd /opt/Anomaly && git pull` - обновить репозиторий
2. ✅ `./CREATE_ENV.sh` - создать .env файл
3. ✅ `nano .env` - заполнить обязательные параметры
4. ✅ `cp env.marzban.template .env.marzban && nano .env.marzban` - настроить Marzban
5. ✅ `docker-compose up -d` - запустить сервисы
6. ✅ `sudo ./setup-ssl.sh` - получить SSL (после распространения DNS)
7. ✅ Обновить .env на HTTPS и перезапустить: `docker-compose restart api bot`


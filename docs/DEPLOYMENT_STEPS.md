# 🚀 Пошаговая инструкция по развертыванию Anomaly Connect

## 📋 Последовательность действий

### Этап 1: Подготовка сервера ⚙️

1. **Подключитесь к VPS #1 (Control Server)**
   ```bash
   ssh root@72.56.79.212
   ```

2. **Установите необходимые пакеты**
   ```bash
   apt update
   apt install -y git docker.io docker-compose
   systemctl enable docker
   systemctl start docker
   ```

3. **Клонируйте репозиторий**
   ```bash
   cd /opt
   git clone https://github.com/Dtroity/Anomaly.git
   cd Anomaly
   ```

### Этап 2: Настройка DNS 🌐

**ВАЖНО: Сделайте это ДО получения SSL!**

1. Откройте панель Timeweb Cloud
2. Перейдите в **Домены и SSL** → **DNS**
3. Создайте следующие A записи:

   ```
   Тип: A | Имя: @ | IP: 72.56.79.212 | TTL: 600
   Тип: A | Имя: api | IP: 72.56.79.212 | TTL: 600
   Тип: A | Имя: panel | IP: 72.56.79.212 | TTL: 600
   ```

4. **Подождите 10-30 минут** для распространения DNS

5. Проверьте DNS:
   ```bash
   nslookup api.anomaly-connect.online
   # Должен вернуть: 72.56.79.212
   ```

📖 **Подробнее:** см. `docs/DNS_SETUP.md`

### Этап 3: Настройка .env файла 📝

1. **Скопируйте шаблон**
   ```bash
   cp env.before-ssl.template .env
   ```

2. **Отредактируйте .env** (используйте HTTP до получения SSL!)
   ```bash
   nano .env
   ```

3. **Обязательные параметры:**
   ```env
   BOT_TOKEN=your_bot_token_from_botfather
   ADMIN_IDS=your_telegram_id
   DB_PASSWORD=strong_password_here
   MARZBAN_PASSWORD=strong_password_here
   YOOKASSA_SHOP_ID=your_shop_id
   YOOKASSA_SECRET_KEY=your_secret_key
   API_SECRET_KEY=$(openssl rand -hex 32)
   
   # ⚠️ ВАЖНО: Используйте HTTP до получения SSL!
   APP_URL=http://api.anomaly-connect.online
   PANEL_URL=http://panel.anomaly-connect.online
   ```

4. **Настройте Marzban .env**
   ```bash
   cp env.marzban.template .env.marzban
   nano .env.marzban
   ```

### Этап 4: Первый запуск 🚀

1. **Запустите сервисы**
   ```bash
   docker-compose up -d
   ```

2. **Проверьте статус**
   ```bash
   docker-compose ps
   docker-compose logs -f
   ```

3. **Проверьте доступность (HTTP)**
   ```bash
   curl http://api.anomaly-connect.online
   ```

### Этап 5: Получение SSL сертификата 🔐

**ВАЖНО: Делайте это только после того, как DNS распространился!**

1. **Откройте порты** (выберите подходящий способ для вашей системы)
   
   **Если используется ufw:**
   ```bash
   ufw allow 80/tcp
   ufw allow 443/tcp
   ```
   
   **Если используется iptables:**
   ```bash
   iptables -A INPUT -p tcp --dport 80 -j ACCEPT
   iptables -A INPUT -p tcp --dport 443 -j ACCEPT
   ```
   
   **Если используется firewalld:**
   ```bash
   firewall-cmd --permanent --add-port=80/tcp
   firewall-cmd --permanent --add-port=443/tcp
   firewall-cmd --reload
   ```
   
   **Или отключите файрвол полностью (не рекомендуется для продакшена):**
   ```bash
   # Для ufw:
   ufw disable
   
   # Для iptables:
   iptables -F
   
   # Для firewalld:
   systemctl stop firewalld
   ```

2. **Запустите скрипт настройки SSL**
   ```bash
   chmod +x setup-ssl.sh
   sudo ./setup-ssl.sh
   ```

   Или вручную:
   ```bash
   sudo apt install certbot python3-certbot-nginx
   docker-compose stop nginx
   sudo certbot certonly --standalone \
     -d anomaly-connect.online \
     -d api.anomaly-connect.online \
     -d panel.anomaly-connect.online \
     --email your-email@example.com \
     --agree-tos
   
   sudo cp /etc/letsencrypt/live/anomaly-connect.online/fullchain.pem nginx/ssl/
   sudo cp /etc/letsencrypt/live/anomaly-connect.online/privkey.pem nginx/ssl/
   docker-compose start nginx
   ```

📖 **Подробнее:** см. `docs/SSL_SETUP.md`

### Этап 6: Обновление .env для HTTPS 🔄

1. **Обновите .env файл**
   ```bash
   nano .env
   ```

2. **Измените URL на HTTPS:**
   ```env
   APP_URL=https://api.anomaly-connect.online
   PANEL_URL=https://panel.anomaly-connect.online
   ```

3. **Перезапустите сервисы**
   ```bash
   docker-compose restart api bot
   ```

### Этап 7: Проверка работы ✅

1. **Проверьте HTTPS**
   ```bash
   curl -I https://api.anomaly-connect.online
   ```

2. **Проверьте бота в Telegram**
   - Найдите вашего бота
   - Отправьте `/start`
   - Проверьте ответ

3. **Проверьте API**
   ```bash
   curl https://api.anomaly-connect.online/health
   ```

4. **Проверьте панель Marzban** (только через VPN или ограниченный IP)
   ```bash
   curl https://panel.anomaly-connect.online/marzban/
   ```

### Этап 8: Настройка автоматических задач ⏰

1. **Настройте cron для бэкапов**
   ```bash
   chmod +x setup-cron.sh
   sudo ./setup-cron.sh
   ```

2. **Проверьте cron задачи**
   ```bash
   crontab -l
   ```

## 🔧 Настройка Node (VPS #2)

1. **Подключитесь к VPS #2**
   ```bash
   ssh root@<node-ip>
   ```

2. **Установите Docker**
   ```bash
   apt update
   apt install -y docker.io docker-compose
   ```

3. **Клонируйте репозиторий**
   ```bash
   cd /opt
   git clone https://github.com/Dtroity/Anomaly.git
   cd Anomaly
   ```

4. **Настройте .env.node**
   ```bash
   cp env.node.template .env.node
   nano .env.node
   ```

5. **Запустите Node**
   ```bash
   docker-compose -f docker-compose.node.yml up -d
   ```

## 📊 Мониторинг

### Просмотр логов

```bash
# Все сервисы
docker-compose logs -f

# Конкретный сервис
docker-compose logs -f bot
docker-compose logs -f api
docker-compose logs -f nginx
```

### Проверка статуса

```bash
docker-compose ps
docker-compose top
```

### Проверка базы данных

```bash
docker-compose exec db psql -U anomaly -d anomaly
```

## 🆘 Решение проблем

### DNS не распространяется

- Подождите 30-60 минут
- Проверьте через разные DNS серверы: `nslookup api.anomaly-connect.online 8.8.8.8`
- Убедитесь, что TTL не слишком большой

### SSL не получается

- Проверьте, что DNS распространился
- Убедитесь, что порт 80 открыт
- Проверьте логи: `docker-compose logs nginx`

### Бот не отвечает

- Проверьте BOT_TOKEN в .env
- Проверьте логи: `docker-compose logs bot`
- Убедитесь, что бот запущен: `docker-compose ps bot`

### API не доступен

- Проверьте Nginx: `docker-compose logs nginx`
- Проверьте API: `docker-compose logs api`
- Проверьте порты: `netstat -tulpn | grep 80`

---

**Готово!** 🎉 Ваш сервис Anomaly Connect должен быть полностью настроен и работать.


# 🔐 Настройка SSL сертификата для Anomaly Connect

## 📋 Предварительные требования

1. ✅ DNS записи настроены и распространились
2. ✅ Порты 80 и 443 открыты на сервере
3. ✅ Домен указывает на IP сервера (72.56.79.212)

## 🔧 Получение SSL сертификата через Let's Encrypt

### Вариант 1: Автоматическая настройка (рекомендуется)

Используйте скрипт `setup-ssl.sh`:

```bash
cd /opt/anomaly-vpn
chmod +x setup-ssl.sh
sudo ./setup-ssl.sh
```

Скрипт автоматически:
- Установит Certbot
- Получит сертификаты для всех доменов
- Настроит автоматическое обновление

### Вариант 2: Ручная настройка

#### Шаг 1: Установка Certbot

```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx -y
```

#### Шаг 2: Остановка Nginx (временно)

```bash
cd /opt/anomaly-vpn
docker-compose stop nginx
```

#### Шаг 3: Получение сертификата

```bash
sudo certbot certonly --standalone \
  -d anomaly-connect.online \
  -d api.anomaly-connect.online \
  -d panel.anomaly-connect.online \
  --email your-email@example.com \
  --agree-tos \
  --non-interactive
```

#### Шаг 4: Копирование сертификатов

```bash
# Создайте директорию для SSL
sudo mkdir -p /opt/anomaly-vpn/nginx/ssl

# Скопируйте сертификаты
sudo cp /etc/letsencrypt/live/anomaly-connect.online/fullchain.pem /opt/anomaly-vpn/nginx/ssl/
sudo cp /etc/letsencrypt/live/anomaly-connect.online/privkey.pem /opt/anomaly-vpn/nginx/ssl/

# Установите правильные права
sudo chmod 644 /opt/anomaly-vpn/nginx/ssl/fullchain.pem
sudo chmod 600 /opt/anomaly-vpn/nginx/ssl/privkey.pem
sudo chown -R $USER:$USER /opt/anomaly-vpn/nginx/ssl
```

#### Шаг 5: Настройка автообновления

```bash
# Добавьте в crontab
sudo crontab -e

# Добавьте строку (обновление каждые 12 часов)
0 */12 * * * certbot renew --quiet --deploy-hook "cd /opt/anomaly-vpn && docker-compose restart nginx"
```

## 📝 Обновление .env файла

После получения SSL сертификата обновите `.env`:

```env
# Измените HTTP на HTTPS
APP_URL=https://api.anomaly-connect.online
PANEL_URL=https://panel.anomaly-connect.online
```

## 🔄 Перезапуск сервисов

```bash
cd /opt/anomaly-vpn
docker-compose restart nginx api bot
```

## ✅ Проверка SSL

### Проверка через браузер:

1. Откройте https://api.anomaly-connect.online
2. Должен отображаться зеленый замочек 🔒
3. Сертификат должен быть валидным

### Проверка через командную строку:

```bash
# Проверка сертификата
openssl s_client -connect api.anomaly-connect.online:443 -servername api.anomaly-connect.online

# Проверка через curl
curl -I https://api.anomaly-connect.online
```

### Онлайн проверка:

- https://www.ssllabs.com/ssltest/
- https://www.sslshopper.com/ssl-checker.html

## 🔧 Настройка Nginx для SSL

Убедитесь, что в `nginx/conf.d/default.conf` правильно указаны пути к сертификатам:

```nginx
ssl_certificate /etc/nginx/ssl/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/privkey.pem;
```

## ⚠️ Важные замечания

1. **DNS должен быть настроен ДО получения SSL**
2. **Порты 80 и 443 должны быть открыты**
3. **Let's Encrypt сертификаты действительны 90 дней** (автообновление настроено)
4. **После получения SSL обновите APP_URL и PANEL_URL в .env**

## 🆘 Решение проблем

### Ошибка: "Failed to obtain certificate"

**Причина:** DNS не распространился или порт 80 закрыт

**Решение:**
1. Проверьте DNS: `nslookup api.anomaly-connect.online`
2. Проверьте порт: `sudo ufw allow 80/tcp`
3. Подождите 10-30 минут после настройки DNS

### Ошибка: "Connection refused"

**Причина:** Nginx не запущен или порт занят

**Решение:**
```bash
docker-compose ps
docker-compose logs nginx
```

### Сертификат не обновляется автоматически

**Решение:**
```bash
# Проверьте cron
sudo crontab -l

# Ручное обновление
sudo certbot renew
```

---

**После успешной настройки SSL:**
1. ✅ Обновите `.env` с HTTPS URL
2. ✅ Перезапустите сервисы
3. ✅ Проверьте доступность через HTTPS


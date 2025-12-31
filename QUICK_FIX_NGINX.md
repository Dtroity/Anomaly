# 🔧 Быстрое исправление Nginx

## Проблема
Nginx перезапускается из-за SSL конфигурации без сертификатов.

## Решение (вручную)

```bash
cd /opt/Anomaly

# 1. Остановить Nginx
docker-compose stop nginx

# 2. Переключить конфигурации на HTTP
cd nginx/conf.d

# Сохранить SSL конфигурации
mv default.conf default-ssl.conf.bak 2>/dev/null || true
mv main.conf main-ssl.conf.bak 2>/dev/null || true
mv panel.conf panel-ssl.conf.bak 2>/dev/null || true

# Использовать HTTP конфигурацию
cp default-http-only.conf default.conf

cd ../..

# 3. Запустить только Nginx (без пересоздания других контейнеров)
docker-compose up -d --no-deps nginx

# 4. Проверить статус
docker-compose ps nginx

# 5. Проверить логи
docker-compose logs --tail=20 nginx

# 6. Проверить доступность
curl http://api.anomaly-connect.online/health
```

## Если проблема с docker-compose

Если возникает ошибка 'ContainerConfig', попробуйте:

```bash
# Пересоздать только Nginx контейнер
docker-compose rm -f nginx
docker-compose up -d --no-deps nginx
```

## Проверка бота

```bash
# Проверить логи бота
docker-compose logs --tail=50 bot

# Проверить токен
grep BOT_TOKEN .env

# Перезапустить бота
docker-compose restart bot
docker-compose logs -f bot
```


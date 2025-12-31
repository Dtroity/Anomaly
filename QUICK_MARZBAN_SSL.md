# 🔐 Быстрая настройка SSL для Marzban

## Проблема
Marzban слушает только на `127.0.0.1:62050` без SSL, что делает его недоступным для Nginx.

## Решение

### Шаг 1: Обновить код и отменить локальные изменения

```bash
cd /opt/Anomaly
git stash
git pull
```

### Шаг 2: Скопировать сертификаты в volume Marzban

```bash
# Создать директорию
docker run --rm -v anomaly_marzban_data:/data alpine mkdir -p /data/ssl

# Скопировать сертификаты из nginx/ssl
docker run --rm \
  -v anomaly_marzban_data:/data \
  -v "$(pwd)/nginx/ssl:/certs:ro" \
  alpine sh -c 'cp /certs/fullchain.pem /data/ssl/cert.pem && cp /certs/privkey.pem /data/ssl/key.pem && chmod 644 /data/ssl/cert.pem && chmod 600 /data/ssl/key.pem'
```

### Шаг 3: Обновить .env.marzban

```bash
# Добавить SSL пути
echo "UVICORN_SSL_CERTFILE=/var/lib/marzban/ssl/cert.pem" >> .env.marzban
echo "UVICORN_SSL_KEYFILE=/var/lib/marzban/ssl/key.pem" >> .env.marzban

# Убедиться, что UVICORN_HOST=0.0.0.0
sed -i '/^UVICORN_HOST=/d' .env.marzban
echo "UVICORN_HOST=0.0.0.0" >> .env.marzban
```

### Шаг 4: Перезапустить Marzban

```bash
docker-compose restart marzban
sleep 15

# Проверить логи
docker-compose logs --tail=20 marzban | grep "Uvicorn running"
# Должно быть: "Uvicorn running on https://0.0.0.0:62050"
```

### Шаг 5: Проверить панель

```bash
curl -k https://panel.anomaly-connect.online/
```

## Альтернатива: Использовать скрипт

```bash
cd /opt/Anomaly
git stash
git pull
chmod +x setup-marzban-ssl.sh
sudo ./setup-marzban-ssl.sh
```


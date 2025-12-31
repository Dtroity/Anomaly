# 🔧 Исправление критических ошибок

## Проблемы в логах:

1. ✅ **SQLAlchemy ошибка**: `Attribute name 'metadata' is reserved`
   - **Исправлено**: Переименовано `metadata` → `extra_data` в моделях `Payment` и `SystemLog`

2. ⚠️ **Marzban ошибка**: `FileNotFoundError: /var/lib/marzban/xray_config.json`
   - **Решение**: Создать файл через скрипт `init-marzban.sh`

3. ⚠️ **Nginx ошибка**: `cannot load certificate` (SSL сертификаты отсутствуют)
   - **Решение**: Использовать временную конфигурацию без SSL

## 🔧 Команды для исправления на сервере:

### 1. Обновить код

```bash
cd /opt/Anomaly
git pull
```

### 2. Создать xray_config.json для Marzban

```bash
cd /opt/Anomaly
chmod +x init-marzban.sh
./init-marzban.sh
```

Или вручную:
```bash
docker-compose exec marzban mkdir -p /var/lib/marzban
docker-compose exec marzban bash -c 'echo "{}" > /var/lib/marzban/xray_config.json'
```

### 3. Временно отключить SSL в Nginx

```bash
cd /opt/Anomaly

# Переименовать конфигурации с SSL
mv nginx/conf.d/default.conf nginx/conf.d/default-ssl.conf
mv nginx/conf.d/main.conf nginx/conf.d/main-ssl.conf
mv nginx/conf.d/panel.conf nginx/conf.d/panel-ssl.conf

# Использовать HTTP конфигурацию
cp nginx/conf.d/default-http-only.conf nginx/conf.d/default.conf
```

### 4. Перезапустить сервисы

```bash
cd /opt/Anomaly
docker-compose down
docker-compose up -d --build
```

### 5. Проверить логи

```bash
docker-compose logs -f api bot marzban
```

## После получения SSL:

1. Вернуть SSL конфигурации:
```bash
mv nginx/conf.d/default-ssl.conf nginx/conf.d/default.conf
mv nginx/conf.d/main-ssl.conf nginx/conf.d/main.conf
mv nginx/conf.d/panel-ssl.conf nginx/conf.d/panel.conf
```

2. Перезапустить Nginx:
```bash
docker-compose restart nginx
```


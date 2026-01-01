# Установка Marzban Node

## Автоматическая установка

Выполните на ноде (VPS #2):

```bash
cd /opt/Anomaly
git pull
chmod +x install-marzban-node.sh
./install-marzban-node.sh
```

Скрипт автоматически:
1. ✅ Проверит наличие Docker и Docker Compose
2. ✅ Создаст необходимые директории
3. ✅ Настроит `docker-compose.node.yml` для использования `gozargah/marzban-node:latest`
4. ✅ Поможет получить и настроить SSL сертификат из панели
5. ✅ Запустит контейнер marzban-node

## Ручная установка (если нужно)

### 1. Получить сертификат из панели

1. Откройте: https://panel.anomaly-connect.online/dashboard/
2. Перейдите в **Nodes** → ваша нода
3. Нажмите **"Скачать сертификат"** (Download Certificate)
4. Скопируйте содержимое сертификата

### 2. Сохранить сертификат на ноде

```bash
cd /opt/Anomaly
mkdir -p node-certs
vi node-certs/ssl_client_cert.pem
# Вставьте содержимое сертификата и сохраните
chmod 644 node-certs/ssl_client_cert.pem
```

### 3. Запустить marzban-node

```bash
cd /opt/Anomaly
docker-compose -f docker-compose.node.yml pull
docker-compose -f docker-compose.node.yml up -d
```

### 4. Проверить статус

```bash
docker-compose -f docker-compose.node.yml ps
docker-compose -f docker-compose.node.yml logs -f marzban-node
```

## Настройка в панели Marzban

После запуска ноды:

1. Откройте панель: https://panel.anomaly-connect.online/dashboard/
2. Перейдите в **Nodes** → **Add Node** (или отредактируйте существующую)
3. Заполните:
   - **Имя:** Node 1 (или ваше имя)
   - **Адрес:** IP адрес ноды (например, `185.126.67.67`)
   - **Порт:** `62050`
   - **API порт:** `62051`
   - **Коэффициент использования:** `1`
4. Нажмите **"Добавить узел"** или **"Сохранить"**
5. Нода должна автоматически подключиться

## Проверка подключения

После добавления ноды в панели:

- Статус должен измениться с "Ошибка" на "Подключено"
- Ошибка `(404, 'Not Found')` должна исчезнуть
- В логах ноды не должно быть ошибок подключения

## Устранение проблем

### Нода не подключается

1. Проверьте логи:
   ```bash
   docker-compose -f docker-compose.node.yml logs -f marzban-node
   ```

2. Убедитесь, что сертификат правильный:
   ```bash
   head -n 1 node-certs/ssl_client_cert.pem
   # Должно быть: -----BEGIN CERTIFICATE-----
   ```

3. Проверьте доступность Control Server с ноды:
   ```bash
   curl -k https://api.anomaly-connect.online/health
   ```

4. Проверьте firewall:
   ```bash
   # Если используется UFW
   ufw status
   # Порты 443, 80, 62050 должны быть открыты
   ```

### Ошибка "Connection refused"

- Убедитесь, что Control Server доступен
- Проверьте, что сертификат правильный
- Проверьте логи ноды на наличие ошибок SSL

### Ошибка 404

- Убедитесь, что используется `marzban-node`, а не обычный Marzban
- Проверьте, что `SERVICE_PROTOCOL=rest` в docker-compose.node.yml
- Убедитесь, что порты указаны правильно в панели

## Структура файлов

```
/opt/Anomaly/
├── docker-compose.node.yml    # Конфигурация Docker Compose для ноды
├── node-certs/
│   └── ssl_client_cert.pem    # SSL сертификат клиента (из панели)
├── node-data/                 # Данные ноды (создается автоматически)
└── .env.node                  # Переменные окружения (не используется marzban-node)
```

## Примечания

- `marzban-node` использует `network_mode: host`, поэтому порты открываются напрямую на хосте
- Сертификат должен быть получен из панели Marzban на Control Server
- Нода подключается к Control Server инициативно (outbound), не требует входящих соединений
- После установки старый контейнер (если был) будет автоматически остановлен


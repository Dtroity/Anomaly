# Настройка Inbounds в Marzban

## Проблема
В Marzban нет настроенных inbounds для VPN протоколов (VMess, VLESS, Trojan, Shadowsocks), поэтому бот не может создавать пользователей.

## Решение

### Вариант 1: Через веб-интерфейс (рекомендуется)

1. Откройте панель Marzban: https://panel.anomaly-connect.online
2. Войдите как администратор (Admin)
3. Перейдите в **Settings** → **Inbounds** (или **⚙️ Основные настройки**)
4. Нажмите **"Добавить"** или **"Create Inbound"**
5. Выберите протокол (рекомендуется **VMess**)
6. Настройте параметры:
   - **Port**: 443 (или другой свободный порт)
   - **Network**: TCP
   - **Security**: TLS или Reality
   - **Tag**: VMess TCP (или другое имя)

### Вариант 2: Через редактирование конфигурации Xray

Если в панели нет раздела для создания inbounds, можно добавить их напрямую в конфигурацию:

1. Откройте панель Marzban: https://panel.anomaly-connect.online
2. Перейдите в **Settings** → **Configuration** (или **⚙️ Основные настройки**)
3. Найдите раздел `inbounds` в JSON конфигурации
4. Добавьте новый inbound для VMess:

```json
{
  "tag": "VMess TCP",
  "protocol": "vmess",
  "listen": "0.0.0.0",
  "port": 443,
  "settings": {
    "clients": []
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "certificates": [
        {
          "certificateFile": "/var/lib/marzban/ssl/certificate.pem",
          "keyFile": "/var/lib/marzban/ssl/key.pem"
        }
      ]
    }
  }
}
```

5. Сохраните конфигурацию
6. Перезапустите Marzban: `docker-compose restart marzban`

### Вариант 3: Использовать готовые шаблоны

В некоторых версиях Marzban есть готовые шаблоны inbounds. Проверьте раздел **Templates** или **Шаблоны** в панели.

## Проверка

После настройки inbounds проверьте:

```bash
cd /opt/Anomaly
./check-marzban-protocols.sh
```

Должен появиться хотя бы один протокол (VMess, VLESS, Trojan или Shadowsocks).

## После настройки

1. Перезапустите бота (если нужно): `./restart-bot-with-new-code.sh`
2. Проверьте в Telegram: `/start` → "Подкл" (Connect)
3. Бот должен создать пользователя и выдать ключ доступа


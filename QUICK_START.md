# Быстрый старт Anomaly VPN

## 🚀 Установка за 3 шага

### Шаг 1: VPS #2 - Установка Marzban

```bash
# На VPS #2 (VPN Node)
cd /opt
git clone <repository-url> anomaly-vpn
cd anomaly-vpn
sudo bash marzban-setup.sh

# Настройте пароль в /opt/marzban/.env
sudo nano /opt/marzban/.env
sudo systemctl restart marzban
```

### Шаг 2: VPS #1 - Установка бота

```bash
# На VPS #1 (Control Plane)
cd /opt
git clone <repository-url> anomaly-vpn
cd anomaly-vpn

# Настройте .env
cp .env.template .env
sudo nano .env

# Установите
sudo bash install.sh
```

### Шаг 3: Проверка

```bash
# Проверьте статус
systemctl status anomaly-bot
systemctl status anomaly-api

# Отправьте /start боту в Telegram
```

## ✅ Готово!

Теперь ваш VPN-сервис работает. Все компоненты установлены **напрямую на VPS** через systemd.

---

📚 Подробная документация: `DEPLOYMENT.md` и `INSTALL_DIRECT.md`


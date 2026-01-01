# Исправление ошибки 404 для ноды Marzban

## Проблема
Control Server получает ошибку `(404, 'Not Found')` при попытке подключиться к ноде через endpoints `/connect` и `/disconnect`.

## Причина
Обычный Marzban (Marzban-0.8.4) не предоставляет endpoints `/connect` и `/disconnect`. Эти endpoints должны быть в отдельном проекте `marzban-node`.

## Решение

### Вариант 1: Использовать marzban-node (рекомендуется)

Marzban Node - это отдельный проект: https://github.com/gozargah/marzban-node

1. Клонировать marzban-node на ноду:
```bash
cd /opt/Anomaly
git clone https://github.com/gozargah/marzban-node.git
cd marzban-node
```

2. Настроить marzban-node согласно его документации

3. Обновить `docker-compose.node.yml` для использования marzban-node

### Вариант 2: Использовать RPyC вместо REST API

В коде Marzban есть поддержка RPyC для подключения нод. Это может работать без endpoints `/connect` и `/disconnect`.

Проверьте настройки ноды в панели:
- Убедитесь, что используется правильный тип подключения (REST или RPyC)
- Проверьте, что API порт указан правильно

### Вариант 3: Временное решение - использовать один сервер

Если ноды не критичны на данный момент, можно использовать только Control Server без нод. Все пользователи будут подключаться напрямую к Control Server.

## Проверка

После применения решения:
1. Проверьте логи ноды: `docker-compose -f docker-compose.node.yml logs marzban-node`
2. В панели Marzban нажмите "Переподключиться" для ноды
3. Ошибка должна исчезнуть


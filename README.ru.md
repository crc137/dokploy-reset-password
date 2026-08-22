<div align="center">
  <a href="https://github.com/coonlink">
    <img width="90px" src="https://raw.coonlink.com/cloud/logo.d.svg" alt="Logo" />
  </a>
  <h1>Reset Password API Server for Dokploy</h1>

[![English](https://img.shields.io/badge/lang-English%20🇺🇸-white)](README.md)
[![Русский](https://img.shields.io/badge/язык-Русский%20🇷🇺-white)](README.ru.md)

<img alt="last-commit" src="https://img.shields.io/github/last-commit/crc137/dokploy-reset-password?style=flat&amp;logo=git&amp;logoColor=white&amp;color=0080ff" style="margin: 0px 2px;">
<img alt="repo-top-language" src="https://img.shields.io/github/languages/top/crc137/dokploy-reset-password?style=flat&amp;color=0080ff" style="margin: 0px 2px;">
<img alt="repo-language-count" src="https://img.shields.io/github/languages/count/crc137/dokploy-reset-password?style=flat&amp;color=0080ff" style="margin: 0px 2px;">
<img alt="version" src="https://img.shields.io/badge/version-1.2.0-blue" style="margin: 0px 2px;">
</div>

<br />

<div align="center">
  <p>В настоящее время в панели Dokploy отсутствует встроенный API для сброса пароля администратора.<br />
    Этот скрипт решает эту проблему, предоставляя простой HTTP API для автоматизации процесса сброса пароля.</p>
</div>

## Установка

```bash
curl -sSL https://raw.coonlink.com/cloud/dokploy-reset-password/install.sh | bash
```

> [!WARNING]  
> Скрипт установки пытается установить необходимые системные пакеты и зависимости Python. Запустите его с правами root, если некоторые системные пакеты не устанавливаются.

## Конфигурация

Настройки хранятся в файле `.env`.
Создайте или отредактируйте файл `.env` в директории установки:

```env
# API ключ для защиты API (ОБЯЗАТЕЛЬНО - сервер отклоняет любой запрос,
# пока ключ не задан; режима без аутентификации больше нет)
API_KEY=your-secret-api-key-here

# Порт для API сервера (по умолчанию: 11292)
API_PORT=11292

# Режим работы по умолчанию
# true - автоматический поиск контейнера Dokploy
# false - ручной режим (требуется указать container_id в запросе)
AUTO_MODE=false

# Сетевой доступ (по умолчанию: true = 0.0.0.0).
# У этого API нет собственного TLS - разместите перед ним TLS-прокси
# (например, Traefik, который уже использует Dokploy), либо установите
# false, чтобы ограничиться 127.0.0.1. См. раздел "Безопасность" ниже.
PUBLIC_BIND=true

# Автоматическая проверка обновлений
# true - автоматически устанавливать новые обновления при их наличии
# false - только отправлять уведомление в Telegram о новых обновлениях (требуется ручная установка)
AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=false

# Уведомления Telegram (опционально)
# TG_TOKEN - токен Telegram бота для уведомлений об обновлениях
# TG_ADMIN - ID чата Telegram для получения уведомлений
TG_TOKEN=
TG_ADMIN=
```

Отредактируйте `.env` и перезапустите сервис для применения изменений:

```bash
sudo systemctl restart reset-password-api-dokploy
```

## Безопасность

- **По умолчанию привязка к `0.0.0.0`.** Установите `PUBLIC_BIND=false` в `.env`, чтобы ограничиться `127.0.0.1`. У сервиса нет собственного TLS - разместите перед ним TLS-прокси (например, Traefik, который уже использует Dokploy), либо используйте SSH-туннель/VPN, если переключитесь на localhost-only.
- **Аутентификация обязательна.** Без `API_KEY` сервис отклоняет все запросы - открытого режима больше нет.
- **Ограничение частоты запросов.** Не более 10 запросов с одного IP за 5 минут на эндпоинт сброса пароля (настраивается только в коде), что соответствует рекомендациям OWASP по блокировке. Учитывается только реальный IP соединения, `X-Forwarded-For` игнорируется, чтобы его нельзя было подделать.
- **`container_id` проверяется** по правилам именования контейнеров Docker перед передачей в `docker exec`.

## Использование

### Проверка статуса панели

Проверьте, доступна ли сама панель Dokploy, прежде чем вызывать сброс пароля (проксирует собственный эндпоинт Dokploy `settings.health`):

```bash
curl -H 'X-API-Key: your_api_key' http://localhost:11292/api/v1/panel-status
```

```json
{
  "success": true,
  "open": true,
  "detail": "ok"
}
```

`open: false` означает, что Dokploy не ответил как исправный - `detail` объясняет причину (`unreachable`, `unhealthy (HTTP ...)` или `misconfigured`, если `DOKPLOY_URL` не является корректным `http(s)://` адресом). Настройте `DOKPLOY_URL` в `.env`, если Dokploy работает не на стандартном `http://127.0.0.1:3000`.

### Сброс пароля - Ручной режим

Укажите ID контейнера вручную:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"container_id": "your-container-id"}'
```

Или используя старое имя поля:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"DOKPLOY_ID_DOCKER": "your-container-id"}'
```

### Сброс пароля - Автоматический режим

Автоматически найти и использовать контейнер Dokploy:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"auto_mode": true}'
```

Или используя параметр `mode`:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"mode": "auto"}'
```

**Ответ при успехе:**
```json
{
  "success": true,
  "password": "new_generated_password",
  "container_id": "9edaf0cc317c",
  "mode": "auto"
}
```

### Логика выбора режима

1. **Приоритет 1**: Если указан `auto_mode` или `mode` в запросе, используется это значение
2. **Приоритет 2**: Если указан `container_id` или `DOKPLOY_ID_DOCKER`, используется ручной режим
3. **Приоритет 3**: Используется значение `AUTO_MODE` из файла `.env`

### Управление сервисом

```bash
# Проверка статуса
sudo systemctl status reset-password-api-dokploy

# Просмотр логов
sudo journalctl -u reset-password-api-dokploy -f

# Просмотр логов обновлений
tail -f /root/ResetPasswordDeploy/update.log

# Перезапуск
sudo systemctl restart reset-password-api-dokploy
```

## Автоматические обновления

Система включает механизм автоматических обновлений, который проверяет наличие новых версий ежедневно в 2:00 ночи.

### Настройка обновлений

- **AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=true**: Автоматически устанавливает новые обновления при их наличии
- **AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=false**: Только отправляет уведомление в Telegram (требуется ручная установка)

### Ручная проверка обновлений

```bash
# Проверить наличие обновлений вручную
/root/ResetPasswordDeploy/update.sh

# Просмотр логов обновлений
tail -f /root/ResetPasswordDeploy/update.log
```

## Удаление

```bash
cd /root/ResetPasswordDeploy
./uninstall.sh
```

## Требования

- Python 3.9+ (требуется для Flask 3.x и waitress; `install.sh` проверяет версию и не продолжит установку на более старой)
- Docker
- Доступ к Docker контейнеру Dokploy
- Права sudo

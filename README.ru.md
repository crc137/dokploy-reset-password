<div align="center">
  <a href="https://github.com/coonlink">
    <img width="90px" src="logo-d.svg" alt="Logo" />
  </a>
  <h1>Reset Password API Server for Dokploy</h1>

[![English](https://img.shields.io/badge/lang-English%20🇺🇸-white)](README.md)
[![Русский](https://img.shields.io/badge/язык-Русский%20🇷🇺-white)](README.ru.md)

<img alt="last-commit" src="https://img.shields.io/github/last-commit/crc137/dokploy-reset-password?style=flat&amp;logo=git&amp;logoColor=white&amp;color=0080ff" style="margin: 0px 2px;">
<img alt="repo-top-language" src="https://img.shields.io/github/languages/top/crc137/dokploy-reset-password?style=flat&amp;color=0080ff" style="margin: 0px 2px;">
<img alt="repo-language-count" src="https://img.shields.io/github/languages/count/crc137/dokploy-reset-password?style=flat&amp;color=0080ff" style="margin: 0px 2px;">
<img alt="version" src="https://img.shields.io/badge/version-1.1.15-blue" style="margin: 0px 2px;">
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
# API ключ для защиты API (рекомендуется)
API_KEY=your-secret-api-key-here

# Порт для API сервера (по умолчанию: 11292)
API_PORT=11292

# Режим работы по умолчанию
# true - автоматический поиск контейнера Dokploy
# false - ручной режим (требуется указать container_id в запросе)
AUTO_MODE=false

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

## Использование

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

- Python 3.6+
- Docker
- Доступ к Docker контейнеру Dokploy
- Права sudo

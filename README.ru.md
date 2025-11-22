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
<img alt="version" src="https://img.shields.io/badge/version-1.0.0-blue" style="margin: 0px 2px;">
</div>

<br />

<div align="center">
  <p>В настоящее время в панели Dokploy отсутствует встроенный API для сброса пароля администратора.<br />
    Этот скрипт решает эту проблему, предоставляя простой HTTP API для автоматизации процесса сброса пароля.</p>
</div>

## Установка

```bash
curl -sSL https://crc137.github.io/dokploy-reset-password/install.sh | bash
```

> [!WARNING]  
> Скрипт установки пытается установить необходимые системные пакеты и зависимости Python. Запустите его с правами root, если некоторые системные пакеты не устанавливаются.

## Конфигурация

Настройки хранятся в файле `.env`.
Отредактируйте `.env` и перезапустите сервис для применения изменений:

```bash
sudo systemctl restart reset-password-api-dokploy
```

## Использование

### Сброс пароля

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"DOKPLOY_ID_DOCKER": "your-container-id"}'
```

**Ответ при успехе:**
```json
{
  "success": true,
  "password": "new_generated_password"
}
```

### Управление сервисом

```bash
# Проверка статуса
sudo systemctl status reset-password-api-dokploy

# Просмотр логов
sudo journalctl -u reset-password-api-dokploy -f

# Перезапуск
sudo systemctl restart reset-password-api-dokploy
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
- 

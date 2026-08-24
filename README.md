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
<img alt="version" src="https://img.shields.io/badge/version-1.2.2-blue" style="margin: 0px 2px;">
</div>

<br />

<div align="center">
  <p>Currently, Dokploy does not have a built-in API for resetting the administrator password.<br />
    This script solves this problem by providing a simple HTTP API to automate the password reset process.</p>
</div>

## Install

```bash
curl -sSL https://raw.coonlink.com/cloud/dokploy-reset-password/install.sh | bash
```

> [!WARNING]  
> The installer script attempts to install required system packages and Python dependencies. Run it with root privileges if some system packages fail.

## Configuration

Settings are stored in `.env` file.
Create or edit `.env` file in the installation directory:

```env
# API key for securing the API (REQUIRED - the server refuses every
# request until this is set; there is no unauthenticated mode)
API_KEY=your-secret-api-key-here

# API server port (default: 11292)
API_PORT=11292

# Default operation mode
# true - automatically find Dokploy container
# false - manual mode (requires container_id in request)
AUTO_MODE=false

# Automatic updates check
# true - automatically install new updates when available
# false - only send Telegram notification about new updates (manual installation required)
AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=false

# Telegram notifications (optional)
# TG_TOKEN - Telegram bot token for update notifications
# TG_ADMIN - Telegram chat ID for receiving notifications
TG_TOKEN=
TG_ADMIN=
```

## Environment Variables

Create a local env file before running containers:

```bash
cp .env.example .env
```

Edit `.env` and restart the service to apply changes:

```bash
sudo systemctl restart reset-password-api-dokploy
```

## Security

- **Authentication is required.** There is no unauthenticated mode: if `API_KEY` is not set, every request is rejected. The API listens on `0.0.0.0`; if reachable beyond localhost, put a TLS-terminating reverse proxy in front or restrict the port with a firewall.
- **Rate limited.** The reset endpoint allows at most 10 requests per source IP per 5 minutes (not adjustable via `.env` - hardcode changes only), matching OWASP's authentication lockout guidance. This is keyed on the raw connection IP, never on `X-Forwarded-For`, so it can't be bypassed with a spoofed header.
- **`container_id` is validated** against Docker's own container-name syntax before it's ever passed to `docker exec`.

## Usage

### Check Panel Status

Check whether the Dokploy panel itself is up before deciding to call reset-password (proxies Dokploy's own `settings.health` endpoint):

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

`open: false` means Dokploy didn't answer healthy - `detail` says why (`unreachable`, `unhealthy (HTTP ...)`, or `misconfigured` if `DOKPLOY_URL` isn't a valid `http(s)://` URL). Configure `DOKPLOY_URL` in `.env` if Dokploy isn't at the default `http://127.0.0.1:3000`.

### Reset Password - Manual Mode

Specify the container ID manually:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"container_id": "your-container-id"}'
```

Or using the legacy field name:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"DOKPLOY_ID_DOCKER": "your-container-id"}'
```

### Reset Password - Auto Mode

Automatically find and use the Dokploy container:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"auto_mode": true}'
```

Or using the `mode` parameter:

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"mode": "auto"}'
```

**Success response:**
```json
{
  "success": true,
  "password": "new_generated_password",
  "container_id": "9edaf0cc317c",
  "mode": "auto"
}
```

### Mode Selection Logic

1. **Priority 1**: If `auto_mode` or `mode` is specified in the request, use that value
2. **Priority 2**: If `container_id` or `DOKPLOY_ID_DOCKER` is provided, use manual mode
3. **Priority 3**: Use `AUTO_MODE` value from `.env` file

### Service Management

```bash
# Check status
sudo systemctl status reset-password-api-dokploy

# View logs
sudo journalctl -u reset-password-api-dokploy -f

# View update logs
tail -f /root/ResetPasswordDeploy/update.log

# Restart
sudo systemctl restart reset-password-api-dokploy
```

## Automatic Updates

The system includes an automatic update mechanism that checks for new versions daily at 2:00 AM.

### Update Configuration

- **AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=true**: Automatically installs new updates when available
- **AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=false**: Only sends Telegram notification (requires manual installation)

### Manual Update Check

```bash
# Check for updates manually
/root/ResetPasswordDeploy/update.sh

# View update logs
tail -f /root/ResetPasswordDeploy/update.log
```

## Daily Password Reset with Telegram Notification

If `TG_TOKEN` and `TG_ADMIN` are set in `.env`, the service can automatically reset the Dokploy admin password every day and send the new password to Telegram.

To avoid flooding the chat, the script **edits the same message every time**: the message ID is stored in the `tg_password_message_id` file, and each subsequent reset updates that exact message (if the message was deleted, a new one is sent and its ID is stored again).

- Enable/disable: `TG_DAILY_PASSWORD=true/false` in `.env` (default: `true`)
- Schedule: daily at 3:30 AM (cron)
- Log: `tail -f /root/ResetPasswordDeploy/password.log`
- Manual run: `/root/ResetPasswordDeploy/daily-password.sh`
- State file: `/root/ResetPasswordDeploy/tg_password_message_id`

> [!WARNING]
> The password is sent to Telegram in plain text. Use a private chat with your bot and do not forward this message.
## Uninstall

```bash
cd /root/ResetPasswordDeploy
./uninstall.sh
```

This stops and removes the systemd service, the daily update cron job, and closes the API port in the firewall (ufw/firewalld). It then asks whether to also delete all files in `/root/ResetPasswordDeploy` (venv, scripts, and `.env` containing the API key). Add `--yes` to skip the prompts and wipe everything.

One-liners from a fresh server:

```bash
# Interactive (with prompts):
bash <(curl -sSL https://raw.coonlink.com/cloud/dokploy-reset-password/uninstall.sh)

# Full removal without prompts:
curl -sSL https://raw.coonlink.com/cloud/dokploy-reset-password/uninstall.sh | bash -s -- --yes
```

Note: `curl ... | bash --yes` does not work - curl tries to parse `--yes` itself. Use `bash -s -- --yes` (or process substitution) to pass flags to the script.

## Requirements

- Python 3.9+ (required by Flask 3.x and waitress; `install.sh` checks this and refuses to proceed on an older Python)
- Docker
- Access to Dokploy Docker container
- sudo privileges

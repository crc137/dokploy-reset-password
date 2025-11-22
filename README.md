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
  <p>Currently, Dokploy does not have a built-in API for resetting the administrator password.<br />
    This script solves this problem by providing a simple HTTP API to automate the password reset process.</p>
</div>

## Install

```bash
curl -sSL https://crc137.github.io/dokploy-reset-password/install.sh | bash
```

> [!WARNING]  
> The installer script attempts to install required system packages and Python dependencies. Run it with root privileges if some system packages fail.

## Configuration

Settings are stored in `.env` file.
Edit `.env` and restart the service to apply changes:

```bash
sudo systemctl restart reset-password-api-dokploy
```

# Usage

### Reset Password

```bash
curl -X POST http://localhost:11292/api/v1/reset-password \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: your_api_key' \
  -d '{"DOKPLOY_ID_DOCKER": "your-container-id"}'
```

**Success response:**
```json
{
  "success": true,
  "password": "new_generated_password"
}
```

### Service Management

```bash
# Check status
sudo systemctl status reset-password-api-dokploy

# View logs
sudo journalctl -u reset-password-api-dokploy -f

# Restart
sudo systemctl restart reset-password-api-dokploy
```

## Uninstall

```bash
cd /root/ResetPasswordDeploy
./uninstall.sh
```

## Requirements

- Python 3.6+
- Docker
- Access to Dokploy Docker container
- sudo privileges

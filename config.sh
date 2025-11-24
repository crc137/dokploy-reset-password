#!/bin/bash

SCRIPT_DIR="/root/ResetPasswordDeploy"

RAW_BASE_URL="https://raw.coonlink.com/cloud/dokploy-reset-password"

VERSION_URL="${RAW_BASE_URL}/version.json"
INSTALL_SCRIPT_URL="${RAW_BASE_URL}/install.sh"

VERSION="1.1.15"

API_PORT="11292"
SERVICE_NAME="reset-password-api-dokploy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

LOG_FILE="${SCRIPT_DIR}/update.log"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"


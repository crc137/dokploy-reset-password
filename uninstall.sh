#!/bin/bash

SCRIPT_DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_THIS/config.sh" ]; then
    source "$SCRIPT_DIR_THIS/config.sh"
elif [ -f "/root/ResetPasswordDeploy/config.sh" ]; then
    source "/root/ResetPasswordDeploy/config.sh"
else
    SERVICE_NAME="reset-password-api-dokploy"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    RED="\033[0;31m"
    NC="\033[0m"
fi

set -e

echo -e "${BLUE}[*] Uninstalling Reset Password API Server...${NC}"

if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo -e "${YELLOW}[-] Stopping service...${NC}"
    sudo systemctl stop ${SERVICE_NAME}.service
fi

if systemctl is-enabled --quiet ${SERVICE_NAME}.service; then
    echo -e "${YELLOW}[-] Disabling service...${NC}"
    sudo systemctl disable ${SERVICE_NAME}.service
fi

if [ -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}[-] Removing systemd service...${NC}"
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
fi

echo -e "${YELLOW}[-] Cleaning old logs...${NC}"
sudo journalctl --vacuum-time=0s -u ${SERVICE_NAME}.service 2>/dev/null || true

echo -e "${GREEN}[+] Uninstall complete!${NC}"
echo -e "${BLUE}[*] Note: Virtual environment and files in ResetPasswordDeploy directory are not removed.${NC}"


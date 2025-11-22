#!/bin/bash

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

set -e

echo -e "${BLUE}[*] Uninstalling Reset Password API Server...${NC}"

if systemctl is-active --quiet reset-password-api-dokploy.service; then
    echo -e "${YELLOW}[-] Stopping service...${NC}"
    sudo systemctl stop reset-password-api-dokploy.service
fi

if systemctl is-enabled --quiet reset-password-api-dokploy.service; then
    echo -e "${YELLOW}[-] Disabling service...${NC}"
    sudo systemctl disable reset-password-api-dokploy.service
fi

SERVICE_FILE="/etc/systemd/system/reset-password-api-dokploy.service"
if [ -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}[-] Removing systemd service...${NC}"
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
fi

echo -e "${GREEN}[+] Uninstall complete!${NC}"
echo -e "${BLUE}[*] Note: Virtual environment and files in ResetPassword directory are not removed.${NC}"


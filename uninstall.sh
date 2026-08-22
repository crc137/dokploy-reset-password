#!/bin/bash

ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=true ;;
        -h|--help)
            echo "Usage: uninstall.sh [-y|--yes]"
            echo ""
            echo "Options:"
            echo "  -y, --yes   No confirmation prompts; removes everything,"
            echo "              including all files in the deploy directory (.env with API key included)"
            echo "  -h, --help  Show this help"
            exit 0 ;;
        *)
            echo "Unknown option: $arg (use --help)" >&2
            exit 1 ;;
    esac
done

SCRIPT_DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_THIS/config.sh" ]; then
    source "$SCRIPT_DIR_THIS/config.sh"
elif [ -f "/root/ResetPasswordDeploy/config.sh" ]; then
    source "/root/ResetPasswordDeploy/config.sh"
else
    SCRIPT_DIR="/root/ResetPasswordDeploy"
    API_PORT="11292"
    SERVICE_NAME="reset-password-api-dokploy"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    RED="\033[0;31m"
    NC="\033[0m"
fi

set -euo pipefail

echo -e "${BLUE}[*] Uninstalling Reset Password API Server...${NC}"

if systemctl is-active --quiet "${SERVICE_NAME}".service 2>/dev/null; then
    echo -e "${YELLOW}[-] Stopping service...${NC}"
    sudo systemctl stop "${SERVICE_NAME}".service
fi

if systemctl is-enabled --quiet "${SERVICE_NAME}".service 2>/dev/null; then
    echo -e "${YELLOW}[-] Disabling service...${NC}"
    sudo systemctl disable "${SERVICE_NAME}".service > /dev/null
fi

if [ -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}[-] Removing systemd service...${NC}"
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
fi

if crontab -l 2>/dev/null | grep -qE "$SCRIPT_DIR/(update|daily-password)\.sh"; then
    echo -e "${YELLOW}[-] Removing scheduled cron jobs (daily update check + daily password reset)...${NC}"
    (crontab -l 2>/dev/null | grep -vE "$SCRIPT_DIR/(update|daily-password)\.sh" || true) | crontab -
fi

if command -v ufw &> /dev/null && sudo ufw status 2>/dev/null | grep -q "${API_PORT}/tcp"; then
    echo -e "${YELLOW}[-] Closing port ${API_PORT} in firewall (ufw)...${NC}"
    sudo ufw delete allow "${API_PORT}"/tcp
    sudo ufw reload 2>/dev/null || true
elif command -v firewall-cmd &> /dev/null && sudo firewall-cmd --list-ports 2>/dev/null | grep -qw "${API_PORT}/tcp"; then
    echo -e "${YELLOW}[-] Closing port ${API_PORT} in firewall (firewalld)...${NC}"
    sudo firewall-cmd --permanent --remove-port="${API_PORT}"/tcp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
fi

echo -e "${YELLOW}[-] Cleaning old logs...${NC}"
sudo journalctl --vacuum-time=0s -u "${SERVICE_NAME}".service 2>/dev/null || true

REMOVE_FILES=false
if [ "$ASSUME_YES" = "true" ]; then
    REMOVE_FILES=true
elif [ -d "$SCRIPT_DIR" ]; then
    PROMPT="Delete ALL files in $SCRIPT_DIR (venv, scripts and .env containing the API key)? [y/N]: "
    echo ""
    if [ -t 0 ]; then
        read -r -p "$PROMPT" ANSWER || ANSWER=""
    elif [ -r /dev/tty ]; then
        read -r -p "$PROMPT" ANSWER < /dev/tty || ANSWER=""
    else
        ANSWER=""
        echo -e "${YELLOW}[!] Stdin is not a terminal - skipping confirmation.${NC}"
    fi
    if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
        REMOVE_FILES=true
    fi
fi

if [ "$REMOVE_FILES" = "true" ] && [ -d "$SCRIPT_DIR" ]; then
    echo -e "${YELLOW}[-] Removing $SCRIPT_DIR ...${NC}"
    rm -rf "$SCRIPT_DIR"
    echo -e "${GREEN}[+] Files removed${NC}"
else
    echo -e "${BLUE}[*] Keeping files in $SCRIPT_DIR. Delete them manually if no longer needed.${NC}"
fi

echo -e "${GREEN}[+] Uninstall complete!${NC}"

if [ "$REMOVE_FILES" != "true" ]; then
    echo -e "${BLUE}[*] Note: virtual environment and files in $SCRIPT_DIR were kept.${NC}"
    echo -e "${BLUE}[*] For a full wipe, run again with --yes:${NC}"
    echo -e "${BLUE}    curl -sSL <uninstall-url> | bash -s -- --yes${NC}"
fi

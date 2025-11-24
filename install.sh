#!/bin/bash

SCRIPT_DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_THIS/config.sh" ]; then
    source "$SCRIPT_DIR_THIS/config.sh"
elif [ -f "/root/ResetPasswordDeploy/config.sh" ]; then
    source "/root/ResetPasswordDeploy/config.sh"
else
    SCRIPT_DIR="/root/ResetPasswordDeploy"
    RAW_BASE_URL="https://raw.coonlink.com/cloud/dokploy-reset-password"
    API_PORT="11292"
    SERVICE_NAME="${SERVICE_NAME}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    RED="\033[0;31m"
    NC="\033[0m"
    VERSION="1.1.14"
fi


mkdir -p "$SCRIPT_DIR"
chmod 777 "$SCRIPT_DIR"
cd "$SCRIPT_DIR"

echo -e "${BLUE}[*] Installing Reset Password API Server (version ${GREEN}${VERSION}${BLUE})...${NC}"

echo -e "${BLUE}[+] Downloading required files from RAW.COONLINK.COM..${NC}"

if ! command -v curl &> /dev/null && [ ! -f /usr/bin/curl ]; then
    echo -e "${RED}[!] Error: curl is not installed${NC}"
    exit 1
fi

CURL_CMD=$(command -v curl || echo "/usr/bin/curl")

download_file() {
    local url="$1"
    local output="$2"
    if $CURL_CMD -sSLf "$url" -o "$output"; then
        echo -e "${GREEN}[+] Downloaded: $(basename $output)${NC}"
        return 0
    else
        echo -e "${RED}[!] Failed to download: $(basename $output)${NC}"
        return 1
    fi
}

download_file "$RAW_BASE_URL/api_server.py" "$SCRIPT_DIR/api_server.py" || exit 1
chmod +x "$SCRIPT_DIR/api_server.py"

download_file "$RAW_BASE_URL/reset-password-helper.sh" "$SCRIPT_DIR/reset-password-helper.sh" || exit 1
chmod +x "$SCRIPT_DIR/reset-password-helper.sh"

download_file "$RAW_BASE_URL/requirements.txt" "$SCRIPT_DIR/requirements.txt" || exit 1

if ! download_file "$RAW_BASE_URL/.env.example" "$SCRIPT_DIR/.env.example"; then
    echo -e "${YELLOW}[!] .env.example not found on RAW.COONLINK.COM, creating locally...${NC}"
    cat > "$SCRIPT_DIR/.env.example" << EOF
API_PORT=${API_PORT}
API_KEY=
AUTO_MODE=
AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=false
TG_TOKEN=
TG_ADMIN=
EOF
fi

download_file "$RAW_BASE_URL/uninstall.sh" "$SCRIPT_DIR/uninstall.sh" || exit 1
chmod +x "$SCRIPT_DIR/uninstall.sh"

download_file "$RAW_BASE_URL/update.sh" "$SCRIPT_DIR/update.sh" || exit 1
chmod +x "$SCRIPT_DIR/update.sh"

if download_file "$RAW_BASE_URL/config.sh" "$SCRIPT_DIR/config.sh"; then
    chmod +x "$SCRIPT_DIR/config.sh" 2>/dev/null || true
    if [ -f "$SCRIPT_DIR/config.sh" ]; then
        source "$SCRIPT_DIR/config.sh"
    fi
fi

if [ -f "$0" ] && [ "$0" != "$SCRIPT_DIR/install.sh" ]; then
    if [ -r "$0" ]; then
        cp "$0" "$SCRIPT_DIR/install.sh" 2>/dev/null || true
        chmod +x "$SCRIPT_DIR/install.sh" 2>/dev/null || true
    fi
fi

echo -e "${GREEN}[+] All files downloaded and made executable${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[!] Error: python3 is not installed${NC}"
    exit 1
fi

PYTHON_FULL_VERSION=$(python3 --version | awk '{print $2}')
PYTHON_MAJOR_MINOR=$(echo "$PYTHON_FULL_VERSION" | cut -d. -f1,2)
PYTHON_FULL=$(echo "$PYTHON_FULL_VERSION" | cut -d. -f1,2,3)

echo -e "${BLUE}[*] Detected Python version: ${GREEN}$PYTHON_FULL_VERSION${NC}"

install_python_venv() {
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        
        if apt-cache show python${PYTHON_FULL}-venv &> /dev/null 2>&1; then
            echo -e "${BLUE}[+] Installing python${PYTHON_FULL}-venv and python${PYTHON_FULL}-distutils...${NC}"
            sudo apt-get install -y python${PYTHON_FULL}-venv python${PYTHON_FULL}-distutils
            return 0
        fi
        
        if apt-cache show python${PYTHON_MAJOR_MINOR}-venv &> /dev/null 2>&1; then
            echo -e "${BLUE}[+] Installing python${PYTHON_MAJOR_MINOR}-venv...${NC}"
            sudo apt-get install -y python${PYTHON_MAJOR_MINOR}-venv
            return 0
        fi
        
        if apt-cache show python3-venv &> /dev/null 2>&1; then
            echo -e "${BLUE}[+] Installing python3-venv...${NC}"
            sudo apt-get install -y python3-venv
            return 0
        fi
        
        echo -e "${BLUE}[+] Installing python3-full...${NC}"
        sudo apt-get install -y python3-full
        return 0
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3-venv
        return 0
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3-venv
        return 0
    fi
    return 1
}

if ! python3 -c "import venv" &> /dev/null 2>&1; then
    echo -e "${YELLOW}[!] python3-venv not found, installing...${NC}"
    if ! install_python_venv; then
        echo -e "${RED}[!] Error: Could not install python3-venv automatically.${NC}"
        exit 1
    fi
fi

TEST_VENV_DIR="/tmp/test_venv_$$"
if python3 -m venv "$TEST_VENV_DIR" &> /dev/null 2>&1; then
    rm -rf "$TEST_VENV_DIR"
else
    echo -e "${YELLOW}[!] venv creation test failed, installing python3-venv...${NC}"
    if ! install_python_venv; then
        echo -e "${RED}[!] Error: Could not install python3-venv. Please install manually:${NC}"
        echo -e "  ${BLUE}  sudo apt-get update${NC}"
        echo -e "  ${BLUE}  sudo apt-get install python${PYTHON_FULL}-venv python${PYTHON_FULL}-distutils${NC}"
        exit 1
    fi
    rm -rf "$TEST_VENV_DIR" 2>/dev/null || true
fi


set -e

echo -e "${BLUE}[+] Creating virtual environment...${NC}"
python3 -m venv venv

echo -e "${BLUE}[+] Installing Python dependencies...${NC}"
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt


echo -e "${BLUE}[+] Creating systemd service...${NC}"

if [ -z "$API_KEY" ]; then
    API_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || echo "")
    if [ -z "$API_KEY" ]; then
        echo -e "${YELLOW}[!] Warning: Could not generate API key automatically.${NC}"
        echo -e "${YELLOW}[!] Please set API_KEY environment variable manually for security.${NC}"
        echo -e "${BLUE}[*] You can generate one with: openssl rand -hex 32${NC}"
        read -p "Enter API key (or press Enter to skip): " API_KEY
    else
        echo -e "${GREEN}[+] Generated API key: ${NC}$API_KEY"
        echo -e "${YELLOW}[!] IMPORTANT: Save this key! You'll need it in your bot's config.${NC}"
    fi
fi


if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${BLUE}[+] Creating .env file from .env.example...${NC}"
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    if [ -n "$API_KEY" ]; then
        sed -i "s/^API_KEY=$/API_KEY=${API_KEY}/" "$SCRIPT_DIR/.env"
    fi
    if ! grep -q "^API_PORT=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        echo "API_PORT=${API_PORT}" >> "$SCRIPT_DIR/.env"
    else
        sed -i "s/^API_PORT=.*/API_PORT=${API_PORT}/" "$SCRIPT_DIR/.env"
    fi
    echo -e "${GREEN}[+] .env file created at $SCRIPT_DIR/.env${NC}"
else
    if [ -n "$API_KEY" ]; then
        if ! grep -q "^API_KEY=" "$SCRIPT_DIR/.env" 2>/dev/null; then
            echo "API_KEY=${API_KEY}" >> "$SCRIPT_DIR/.env"
        else
            sed -i "s/^API_KEY=.*/API_KEY=${API_KEY}/" "$SCRIPT_DIR/.env"
        fi
    fi
    if ! grep -q "^API_PORT=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        echo "API_PORT=${API_PORT}" >> "$SCRIPT_DIR/.env"
    else
        sed -i "s/^API_PORT=.*/API_PORT=${API_PORT}/" "$SCRIPT_DIR/.env"
    fi
fi

if ! grep -q "^API_PORT=${API_PORT}" "$SCRIPT_DIR/.env" 2>/dev/null; then
    echo -e "${YELLOW}[!] Warning: API_PORT not set to 11292, fixing...${NC}"
    if ! grep -q "^API_PORT=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        echo "API_PORT=${API_PORT}" >> "$SCRIPT_DIR/.env"
    else
        sed -i "s/^API_PORT=.*/API_PORT=${API_PORT}/" "$SCRIPT_DIR/.env"
    fi
fi

sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Reset Password API Server for Dokploy
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/venv/bin/python3 $SCRIPT_DIR/api_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo -e "${BLUE}[+] Reloading systemd...${NC}"
sudo systemctl daemon-reload

if systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
    echo -e "${BLUE}[+] Restarting service to apply .env changes...${NC}"
    sudo systemctl restart ${SERVICE_NAME}.service
    sleep 2
fi

echo -e "${BLUE}[+] Opening port $API_PORT in firewall...${NC}"
if command -v ufw &> /dev/null; then
    echo -e "${BLUE}[+] Opening port $API_PORT in firewall (ufw)...${NC}"
    sudo ufw allow ${API_PORT}/tcp
    sudo ufw reload 2>/dev/null || true
elif command -v firewall-cmd &> /dev/null; then
    echo -e "${BLUE}[+] Opening port $API_PORT in firewall (firewalld)...${NC}"
    sudo firewall-cmd --permanent --add-port=${API_PORT}/tcp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
fi

echo -e "${BLUE}[+] Enabling service...${NC}"
sudo systemctl enable ${SERVICE_NAME}.service

echo -e "${BLUE}[+] Starting service...${NC}"
sudo systemctl start ${SERVICE_NAME}.service

echo -e "${BLUE}[*] Checking service status...${NC}"
sleep 3
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo -e "${GREEN}[+] Service is running${NC}"
else
    echo -e "${RED}[!] Service is not running! Checking logs...${NC}"
    sudo journalctl -u ${SERVICE_NAME} -n 20 --no-pager
    exit 1
fi

echo -e "${BLUE}[*] Checking if port 11292 is listening...${NC}"
if command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q ":${API_PORT} "; then
        echo -e "${GREEN}[+] Port 11292 is listening${NC}"
    else
        echo -e "${YELLOW}[!] Port 11292 is not listening yet, waiting...${NC}"
        sleep 2
        if netstat -tuln | grep -q ":${API_PORT} "; then
            echo -e "${GREEN}[+] Port 11292 is now listening${NC}"
        else
            echo -e "${RED}[!] Port 11292 is still not listening${NC}"
        fi
    fi
elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q ":${API_PORT} "; then
        echo -e "${GREEN}[+] Port 11292 is listening${NC}"
    else
        echo -e "${YELLOW}[!] Port 11292 is not listening yet, waiting...${NC}"
        sleep 2
        if ss -tuln | grep -q ":${API_PORT} "; then
            echo -e "${GREEN}[+] Port 11292 is now listening${NC}"
        else
            echo -e "${RED}[!] Port 11292 is still not listening${NC}"
            echo -e "${YELLOW}[!] Checking service logs for port configuration...${NC}"
            if sudo journalctl -u ${SERVICE_NAME} -n 10 --no-pager | grep -q "11291"; then
                echo -e "${RED}[!] ERROR: Service is running on port 11291 instead of 11292!${NC}"
                echo -e "${YELLOW}[!] Checking .env file...${NC}"
                if [ -f "$SCRIPT_DIR/.env" ]; then
                    echo -e "${BLUE}[*] Current .env API_PORT setting:${NC}"
                    grep "^API_PORT=" "$SCRIPT_DIR/.env" || echo "API_PORT not found in .env"
                    echo -e "${BLUE}[*] Fixing .env file...${NC}"
                    sed -i "s/^API_PORT=.*/API_PORT=${API_PORT}/" "$SCRIPT_DIR/.env"
                    echo -e "${BLUE}[*] Restarting service...${NC}"
                    sudo systemctl restart ${SERVICE_NAME}.service
                    sleep 3
                fi
            fi
        fi
    fi
fi

echo -e "${BLUE}[*] Verifying firewall rules...${NC}"
if command -v ufw &> /dev/null; then
    if sudo ufw status | grep -q "${API_PORT}/tcp"; then
        echo -e "${GREEN}[+] Port $API_PORT is allowed in ufw${NC}"
    else
        echo -e "${YELLOW}[!] Port $API_PORT not found in ufw rules, adding...${NC}"
        sudo ufw allow ${API_PORT}/tcp
        sudo ufw reload 2>/dev/null || true
    fi
fi

sudo systemctl status ${SERVICE_NAME}.service --no-pager

echo ""
echo -e "${GREEN}[+] Installation complete!${NC}"
echo -e "${GREEN}[+] API Server (version ${VERSION}) is running on http://0.0.0.0:${API_PORT}${NC}"
echo ""
echo -e "${BLUE}[*] To test from external IP, use:${NC}"
echo -e "${BLUE}    curl http://$(hostname -I | awk '{print $1}'):${API_PORT}${NC}"
echo ""
if [ -n "$API_KEY" ]; then
    echo -e "${BLUE}[*] API Key: ${NC}$API_KEY"
    echo ""
    echo -e "${YELLOW}[!] Add this to your bot's env file:${NC}"
    echo -e "${GREEN}DOKPLOY_RESET_API_KEY=$API_KEY${NC}"
    echo ""
    echo -e "${BLUE}[*] Test with:${NC}"
    echo "curl -X POST http://localhost:${API_PORT}/api/v1/reset-password \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'X-API-Key: $API_KEY' \\"
    echo "  -d '{\"DOKPLOY_ID_DOCKER\": \"your-container-id\"}'"
else
    echo -e "${RED}[!] API_KEY not set - API is unprotected!${NC}"
    echo -e "${YELLOW}[!] Set it manually in .env file or set environment variable.${NC}"
    echo ""
    echo -e "${BLUE}[*] Test with:${NC} curl -X POST http://localhost:${API_PORT}/api/v1/reset-password -H 'Content-Type: application/json' -d '{\"DOKPLOY_ID_DOCKER\": \"your-container-id\"}'"
fi
echo ""
echo -e "${BLUE}[*] Version:${NC} $VERSION"

echo -e "${BLUE}[+] Setting up daily update check...${NC}"
CRON_JOB="0 2 * * * $SCRIPT_DIR/update.sh >> $SCRIPT_DIR/update.log 2>&1"
(crontab -l 2>/dev/null | grep -v "$SCRIPT_DIR/update.sh"; echo "$CRON_JOB") | crontab -
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[+] Daily update check scheduled (runs at 2:00 AM daily)${NC}"
else
    echo -e "${YELLOW}[!] Warning: Failed to set up cron job. You can manually add:${NC}"
    echo -e "${BLUE}    $CRON_JOB${NC}"
fi

echo ""
echo -e "${BLUE}[*] To check logs:${NC} sudo journalctl -u ${SERVICE_NAME} -f"
echo -e "${BLUE}[*] To check update logs:${NC} tail -f $SCRIPT_DIR/update.log"
echo -e "${BLUE}[*] To manually check for updates:${NC} $SCRIPT_DIR/update.sh"
echo -e "${BLUE}[*] To stop:${NC} sudo systemctl stop ${SERVICE_NAME}"
echo -e "${BLUE}[*] To start:${NC} sudo systemctl start ${SERVICE_NAME}"
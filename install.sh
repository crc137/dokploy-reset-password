#!/bin/bash

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

SCRIPT_DIR="/root/ResetPasswordDeploy"
GITHUB_BASE_URL="https://crc137.github.io/dokploy-reset-password"

mkdir -p "$SCRIPT_DIR"
chmod 777 "$SCRIPT_DIR"
cd "$SCRIPT_DIR"

echo -e "${BLUE}[*] Installing Reset Password API Server...${NC}"

echo -e "${BLUE}[+] Downloading required files from GitHub...${NC}"

if ! command -v curl &> /dev/null; then
    echo -e "${RED}[!] Error: curl is not installed${NC}"
    exit 1
fi

download_file() {
    local url="$1"
    local output="$2"
    if curl -sSLf "$url" -o "$output"; then
        echo -e "${GREEN}[+] Downloaded: $(basename $output)${NC}"
        return 0
    else
        echo -e "${RED}[!] Failed to download: $(basename $output)${NC}"
        return 1
    fi
}

if [ ! -f "$SCRIPT_DIR/api_server.py" ]; then
    download_file "$GITHUB_BASE_URL/api_server.py" "$SCRIPT_DIR/api_server.py" || exit 1
fi

if [ ! -f "$SCRIPT_DIR/reset-password-helper.sh" ]; then
    download_file "$GITHUB_BASE_URL/reset-password-helper.sh" "$SCRIPT_DIR/reset-password-helper.sh" || exit 1
fi

if [ ! -f "$SCRIPT_DIR/requirements.txt" ]; then
    download_file "$GITHUB_BASE_URL/requirements.txt" "$SCRIPT_DIR/requirements.txt" || exit 1
fi

if [ ! -f "$SCRIPT_DIR/.env.example" ]; then
    download_file "$GITHUB_BASE_URL/.env.example" "$SCRIPT_DIR/.env.example" || exit 1
fi

if [ ! -f "$SCRIPT_DIR/uninstall.sh" ]; then
    download_file "$GITHUB_BASE_URL/uninstall.sh" "$SCRIPT_DIR/uninstall.sh" || exit 1
    chmod +x "$SCRIPT_DIR/uninstall.sh"
fi

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

chmod +x reset-password-helper.sh
chmod +x api_server.py

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
        echo "API_PORT=11291" >> "$SCRIPT_DIR/.env"
    fi
fi

SERVICE_FILE="/etc/systemd/system/reset-password-api-dokploy.service"
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

echo -e "${BLUE}[+] Enabling service...${NC}"
sudo systemctl enable reset-password-api-dokploy.service

echo -e "${BLUE}[+] Starting service...${NC}"
sudo systemctl start reset-password-api-dokploy.service

echo -e "${BLUE}[*] Checking service status...${NC}"
sleep 2
sudo systemctl status reset-password-api-dokploy.service --no-pager

echo ""
echo -e "${GREEN}[+] Installation complete!${NC}"
echo -e "${GREEN}[+] API Server is running on http://0.0.0.0:11291${NC}"
echo ""
if [ -n "$API_KEY" ]; then
    echo -e "${BLUE}[*] API Key: ${NC}$API_KEY"
    echo ""
    echo -e "${YELLOW}[!] Add this to your bot's env file:${NC}"
    echo -e "${GREEN}DOKPLOY_RESET_API_KEY=$API_KEY${NC}"
    echo ""
    echo -e "${BLUE}[*] Test with:${NC}"
    echo "curl -X POST http://localhost:11291/api/v1/reset-password \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'X-API-Key: $API_KEY' \\"
    echo "  -d '{\"DOKPLOY_ID_DOCKER\": \"your-container-id\"}'"
else
    echo -e "${RED}[!] API_KEY not set - API is unprotected!${NC}"
    echo -e "${YELLOW}[!] Set it manually in .env file or set environment variable.${NC}"
    echo ""
    echo -e "${BLUE}[*] Test with:${NC} curl -X POST http://localhost:11291/api/v1/reset-password -H 'Content-Type: application/json' -d '{\"DOKPLOY_ID_DOCKER\": \"your-container-id\"}'"
fi
echo ""
echo -e "${BLUE}[*] To check logs:${NC} sudo journalctl -u reset-password-api-dokploy -f"
echo -e "${BLUE}[*] To stop:${NC} sudo systemctl stop reset-password-api-dokploy"
echo -e "${BLUE}[*] To start:${NC} sudo systemctl start reset-password-api-dokploy"
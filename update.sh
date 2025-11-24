#!/bin/bash

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

SCRIPT_DIR="/root/ResetPasswordDeploy"
VERSION_URL="https://raw.coonlink.com/cloud/dokploy-reset-password/version-dokploy-reset-password.json"
INSTALL_SCRIPT_URL="https://raw.coonlink.com/cloud/dokploy-reset-password/install.sh"
LOG_FILE="$SCRIPT_DIR/update.log"

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    case "$level" in
        "INFO")
            echo -e "${BLUE}[*]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[+]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[!]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[!]${NC} $message"
            ;;
    esac
}

get_current_version() {
    local version=""
    
    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        version=$(grep -E '^VERSION=' "$SCRIPT_DIR/install.sh" 2>/dev/null | head -1 | cut -d'"' -f2)
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    echo "1.1.13"
}

version_compare() {
    local version1="$1"
    local version2="$2"
    
    version1="${version1#v}"
    version2="${version2#v}"
    
    IFS='.' read -ra V1 <<< "$version1"
    IFS='.' read -ra V2 <<< "$version2"
    
    for i in "${!V1[@]}"; do
        if [ -z "${V2[$i]}" ]; then
            V2[$i]=0
        fi
        if [ "${V1[$i]}" -gt "${V2[$i]}" ]; then
            echo "1"
            return
        elif [ "${V1[$i]}" -lt "${V2[$i]}" ]; then
            echo "-1"
            return
        fi
    done
    
    if [ ${#V2[@]} -gt ${#V1[@]} ]; then
        for ((i=${#V1[@]}; i<${#V2[@]}; i++)); do
            if [ "${V2[$i]}" -gt 0 ]; then
                echo "-1"
                return
            fi
        done
    fi
    
    echo "0"
}

send_telegram_notification() {
    local message="$1"
    
    local env_file="$SCRIPT_DIR/.env"
    if [ ! -f "$env_file" ]; then
        log_message "WARNING" "Cannot send Telegram notification: .env file not found"
        return 1
    fi
    
    set -a
    source "$env_file" 2>/dev/null
    set +a
    
    if [ -z "$TG_TOKEN" ] || [ -z "$TG_ADMIN" ]; then
        log_message "WARNING" "Cannot send Telegram notification: TG_TOKEN or TG_ADMIN not set in .env"
        return 1
    fi
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_ADMIN}" \
        -d "text=$(echo -e "$message" | sed 's/"/\\"/g')" \
        -d "parse_mode=HTML" 2>&1)
    
    if echo "$response" | grep -q '"ok":true'; then
        log_message "SUCCESS" "Telegram notification sent successfully"
        return 0
    else
        log_message "ERROR" "Failed to send Telegram notification: $response"
        return 1
    fi
}

format_changelog() {
    local changelog_json="$1"
    local version="$2"
    
    if command -v python3 &> /dev/null; then
        python3 << EOF
import json
import sys

try:
    data = json.loads('''$changelog_json''')
    changelog = data.get('changelog', [])
    
    for entry in changelog:
        if entry.get('version') == '$version':
            date = entry.get('date', 'N/A')
            changes = entry.get('changes', [])
            
            print(f"Version: {entry['version']}")
            print(f"Date: {date}")
            print("Changes:")
            if changes:
                for change in changes:
                    print(f"  - {change}")
            else:
                print("  - No changes listed")
            break
    else:
        print(f"Changelog for version $version not found")
except Exception as e:
    print(f"Error parsing changelog: {e}")
EOF
    elif command -v jq &> /dev/null; then
        echo "$changelog_json" | jq -r --arg version "$version" '
            .changelog[] | 
            select(.version == $version) | 
            "Version: \(.version)\nDate: \(.date)\nChanges:\n" + 
            (if .changes | length > 0 then 
                (.changes[] | "  - \(.)") 
            else 
                "  - No changes listed" 
            end)
        '
    else
        echo "Version: $version"
        echo "Changelog parsing requires python3 or jq"
    fi
}

check_for_updates() {
    log_message "INFO" "Checking for updates..."
    
    local current_version=$(get_current_version)
    log_message "INFO" "Current version: $current_version"
    
    local version_file="/tmp/version-dokploy-reset-password.json"
    if ! curl -sSLf "$VERSION_URL" -o "$version_file"; then
        log_message "ERROR" "Failed to download version file from $VERSION_URL"
        return 1
    fi
    
    local new_version=""
    if command -v python3 &> /dev/null; then
        new_version=$(python3 -c "import json; data = json.load(open('$version_file')); print(data.get('install_new_version', ''))" 2>/dev/null)
    elif command -v jq &> /dev/null; then
        new_version=$(jq -r '.install_new_version' "$version_file" 2>/dev/null)
    else    
        new_version=$(grep -oP '"install_new_version":\s*"\K[^"]+' "$version_file" | head -1)
    fi
    
    if [ -z "$new_version" ]; then
        log_message "ERROR" "Failed to parse new version from version file"
        rm -f "$version_file"
        return 1
    fi
    
    log_message "INFO" "Latest available version: $new_version"
    
    local comparison=$(version_compare "$new_version" "$current_version")
    
    if [ "$comparison" -le 0 ]; then
        log_message "INFO" "No update available. Current version ($current_version) is up to date."
        rm -f "$version_file"
        return 0
    fi
    
    log_message "SUCCESS" "New version available: $new_version (current: $current_version)"
    
    local expected_hash=""
    if command -v python3 &> /dev/null; then
        expected_hash=$(python3 -c "import json; data = json.load(open('$version_file')); print(data.get('install_sh_sha256', ''))" 2>/dev/null)
    elif command -v jq &> /dev/null; then
        expected_hash=$(jq -r '.install_sh_sha256 // empty' "$version_file" 2>/dev/null)
    else
        expected_hash=$(grep -oP '"install_sh_sha256":\s*"\K[^"]+' "$version_file" | head -1)
    fi
    
    local changelog_content=$(cat "$version_file")
    local changelog_text=$(format_changelog "$changelog_content" "$new_version")
    
    log_message "INFO" "Changelog for version $new_version:"
    echo "$changelog_text" | while IFS= read -r line; do
        log_message "INFO" "$line"
    done
    
    local env_file="$SCRIPT_DIR/.env"
    local auto_update="false"
    
    if [ -f "$env_file" ]; then
        set -a
        source "$env_file" 2>/dev/null
        set +a
        
        if [ -n "$AUTOMATICALLY_CHECK_FOR_NEW_UPDATES" ]; then
            auto_update=$(echo "$AUTOMATICALLY_CHECK_FOR_NEW_UPDATES" | tr '[:upper:]' '[:lower:]')
        fi
    fi
    
    local notification="<b>New Update Available!</b>

<b>Reset Password API Server</b>

Current version: <code>$current_version</code>
New version: <code>$new_version</code>

<b>Changelog:</b>
<pre>$(echo "$changelog_text" | head -20)</pre>"
    
    if [ "$auto_update" = "true" ] || [ "$auto_update" = "1" ] || [ "$auto_update" = "yes" ] || [ "$auto_update" = "on" ]; then
        log_message "INFO" "AUTO_UPDATE is enabled. Installing new version automatically..."
        
        notification="$notification

<b>Auto-update enabled</b> - Installing now..."
        
        send_telegram_notification "$notification"
        
        local temp_update_script="/tmp/update_clean_install.sh"
        log_message "INFO" "Creating temporary update script..."
        
        local version_file_for_update="/tmp/version-for-update.json"
        cp "$version_file" "$version_file_for_update" 2>/dev/null || true
        
        cat > "$temp_update_script" << UPDATE_SCRIPT_EOF
#!/bin/bash

SCRIPT_DIR="/root/ResetPasswordDeploy"
INSTALL_SCRIPT_URL="https://raw.coonlink.com/cloud/dokploy-reset-password/install.sh"
VERSION_FILE="$version_file_for_update"
VERSION_URL="https://raw.coonlink.com/cloud/dokploy-reset-password/version-dokploy-reset-password.json"
ENV_BACKUP="/tmp/.env.backup.$$"
BACKUP_DIR="/tmp/reset-password-backup-$(date +%Y%m%d-%H%M%S)"
TEMP_SCRIPT_SELF="/tmp/update_clean_install.sh"
INSTALL_NEW="/tmp/install_new.sh"

log_step() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    echo "      → $1"
}

log_error() {
    echo "      ✗ ERROR: $1" >&2
}

log_success() {
    echo "      ✓ $1"
}

echo "=========================================="
log_step "=== Starting clean update process ==="
echo "=========================================="

log_step "[1/8] Stopping service..."
if systemctl is-active --quiet reset-password-api-dokploy.service 2>/dev/null; then
    sudo systemctl stop reset-password-api-dokploy.service || true
    sleep 2
    if systemctl is-active --quiet reset-password-api-dokploy.service 2>/dev/null; then
        log_error "Failed to stop service, forcing stop..."
        sudo systemctl kill -s KILL reset-password-api-dokploy.service 2>/dev/null || true
    fi
    log_success "Service stopped"
else
    log_info "Service was not running"
fi

log_step "[2/8] Creating backup of previous version..."
if [ -d "$SCRIPT_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    log_info "Backup directory: $BACKUP_DIR"
    
    if [ "$(ls -A "$SCRIPT_DIR" 2>/dev/null | grep -v '^\.env$')" ]; then
        cd "$SCRIPT_DIR"
        log_info "Creating backup of old files..."
        
        [ -f "api_server.py" ] && cp "api_server.py" "$BACKUP_DIR/" && log_info "  Backed up: api_server.py"
        [ -f "requirements.txt" ] && cp "requirements.txt" "$BACKUP_DIR/" && log_info "  Backed up: requirements.txt"
        [ -f "reset-password-helper.sh" ] && cp "reset-password-helper.sh" "$BACKUP_DIR/" && log_info "  Backed up: reset-password-helper.sh"
        [ -f "uninstall.sh" ] && cp "uninstall.sh" "$BACKUP_DIR/" && log_info "  Backed up: uninstall.sh"
        [ -f "update.sh" ] && cp "update.sh" "$BACKUP_DIR/" && log_info "  Backed up: update.sh"
        
        if [ -d "venv" ]; then
            log_info "  Backing up venv directory..."
            cp -r "venv" "$BACKUP_DIR/" 2>/dev/null || log_info "  (venv backup skipped - too large)"
        fi
        
        find . -mindepth 1 -maxdepth 1 ! -name '.env' -type f -exec cp {} "$BACKUP_DIR/" \; 2>/dev/null || true
        find . -mindepth 1 -maxdepth 1 ! -name '.env' ! -name 'venv' -type d -exec cp -r {} "$BACKUP_DIR/" \; 2>/dev/null || true
        
        log_success "Backup created in $BACKUP_DIR"
    else
        log_info "No files to backup"
    fi
else
    log_info "Script directory does not exist, skipping backup"
fi

log_step "[3/8] Backing up .env file..."
if [ -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env" "$ENV_BACKUP"
    log_success ".env backed up to $ENV_BACKUP"
else
    log_info "No .env file found, skipping backup"
fi

log_step "[4/8] Removing old files..."
if [ -d "$SCRIPT_DIR" ]; then
    cd "$SCRIPT_DIR"
    
    log_info "Removing old files..."
    
    [ -f "api_server.py" ] && rm -f "api_server.py" && log_info "  Removed: api_server.py"
    [ -f "requirements.txt" ] && rm -f "requirements.txt" && log_info "  Removed: requirements.txt"
    [ -f "reset-password-helper.sh" ] && rm -f "reset-password-helper.sh" && log_info "  Removed: reset-password-helper.sh"
    [ -f "uninstall.sh" ] && rm -f "uninstall.sh" && log_info "  Removed: uninstall.sh"
    [ -f "update.sh" ] && rm -f "update.sh" && log_info "  Removed: update.sh"
    
    log_info "  Removing directories..."
    [ -d "venv" ] && rm -rf "venv" && log_info "  Removed: venv/"
    [ -d "__pycache__" ] && rm -rf "__pycache__" && log_info "  Removed: __pycache__/"
    [ -d ".pytest_cache" ] && rm -rf ".pytest_cache" && log_info "  Removed: .pytest_cache/"
    
    log_info "  Removing any remaining files..."
    find . -mindepth 1 -maxdepth 1 ! -name '.env' -type f -delete 2>/dev/null || true
    find . -mindepth 1 -maxdepth 1 ! -name '.env' -type d -exec rm -rf {} + 2>/dev/null || true
    
    for item in "$SCRIPT_DIR"/*; do
        if [ -e "$item" ] && [ "$(basename "$item")" != ".env" ]; then
            rm -rf "$item" 2>/dev/null && log_info "  Force removed: $(basename "$item")"
        fi
    done
    
    log_success "All old files removed (kept .env)"
else
    log_info "Script directory does not exist"
    mkdir -p "$SCRIPT_DIR"
fi

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    local delay=2
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Download attempt $attempt of $max_attempts..."
        if curl -sSLf "$url" -o "$output"; then
            return 0
        fi
        if [ $attempt -lt $max_attempts ]; then
            log_info "Download failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

calculate_sha256() {
    local file="$1"
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        echo ""
    fi
}

verify_installation() {
    local max_wait=30
    local wait_time=0
    local check_interval=2
    
    log_info "Verifying installation..."
    
    sleep 3
    if systemctl is-active --quiet reset-password-api-dokploy.service 2>/dev/null; then
        log_success "Service is running"
    else
        log_error "Service is not running"
        return 1
    fi
    
    while [ $wait_time -lt $max_wait ]; do
        if command -v netstat &> /dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":11292 "; then
                log_success "Port 11292 is listening"
                return 0
            fi
        elif command -v ss &> /dev/null; then
            if ss -tuln 2>/dev/null | grep -q ":11292 "; then
                log_success "Port 11292 is listening"
                return 0
            fi
        fi
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
        log_info "Waiting for port 11292 to be available... (${wait_time}s/${max_wait}s)"
    done
    
    log_error "Port 11292 is not listening after ${max_wait}s"
    return 1
}

log_step "[5/8] Downloading new install script with retry..."
if download_with_retry "$INSTALL_SCRIPT_URL" "$INSTALL_NEW"; then
    if [ ! -f "$INSTALL_NEW" ]; then
        log_error "Downloaded file does not exist"
        exit 1
    fi
    
    file_size=$(stat -f%z "$INSTALL_NEW" 2>/dev/null || stat -c%s "$INSTALL_NEW" 2>/dev/null || echo "0")
    if [ "$file_size" -eq 0 ]; then
        log_error "Downloaded file is empty"
        rm -f "$INSTALL_NEW"
        exit 1
    fi
    
    if ! grep -q "VERSION=" "$INSTALL_NEW" 2>/dev/null; then
        log_error "Downloaded file does not appear to be a valid install script (no VERSION found)"
        rm -f "$INSTALL_NEW"
        exit 1
    fi
    
    log_info "Calculating SHA256 hash..."
    file_hash=$(calculate_sha256 "$INSTALL_NEW")
    if [ -z "$file_hash" ]; then
        log_error "SHA256 calculation not available (sha256sum/shasum not found)"
        log_error "Cannot verify file integrity"
        rm -f "$INSTALL_NEW"
        exit 1
    fi
    
    log_success "File SHA256: $file_hash"
    
    log_info "Verifying SHA256 hash against server..."
    expected_hash=""
    
    if [ -f "$VERSION_FILE" ]; then
        if command -v python3 &> /dev/null; then
            expected_hash=$(python3 -c "import json; data = json.load(open('$VERSION_FILE')); print(data.get('install_sh_sha256', ''))" 2>/dev/null)
        elif command -v jq &> /dev/null; then
            expected_hash=$(jq -r '.install_sh_sha256 // empty' "$VERSION_FILE" 2>/dev/null)
        else
            expected_hash=$(grep -oP '"install_sh_sha256":\s*"\K[^"]+' "$VERSION_FILE" | head -1)
        fi
    fi
    
    if [ -z "$expected_hash" ]; then
        log_info "Hash not found in saved version file, downloading from server..."
        local temp_version="/tmp/version-check.json"
        if curl -sSLf "$VERSION_URL" -o "$temp_version" 2>/dev/null; then
            if command -v python3 &> /dev/null; then
                expected_hash=$(python3 -c "import json; data = json.load(open('$temp_version')); print(data.get('install_sh_sha256', ''))" 2>/dev/null)
            elif command -v jq &> /dev/null; then
                expected_hash=$(jq -r '.install_sh_sha256 // empty' "$temp_version" 2>/dev/null)
            else
                expected_hash=$(grep -oP '"install_sh_sha256":\s*"\K[^"]+' "$temp_version" | head -1)
            fi
            rm -f "$temp_version"
        fi
    fi
    
    if [ -n "$expected_hash" ] && [ "$expected_hash" != "" ]; then
        if [ "$file_hash" = "$expected_hash" ]; then
            log_success "SHA256 hash verification passed!"
        else
            log_error "SHA256 hash verification FAILED!"
            log_error "Expected: $expected_hash"
            log_error "Got:      $file_hash"
            log_error "File integrity check failed. Aborting installation for security."
            rm -f "$INSTALL_NEW"
            exit 1
        fi
    else
        log_info "Expected hash not found in version file, skipping hash verification"
        log_info "Warning: File integrity cannot be verified"
    fi
    
    downloaded_version=$(grep -E '^VERSION=' "$INSTALL_NEW" | head -1 | cut -d'"' -f2)
    if [ -n "$downloaded_version" ]; then
        log_success "Install script downloaded successfully (version: $downloaded_version, size: $file_size bytes)"
    else
        log_success "Install script downloaded successfully (size: $file_size bytes)"
    fi
    
    chmod +x "$INSTALL_NEW"
    
    log_step "[6/8] Restoring .env file..."
    if [ -f "$ENV_BACKUP" ]; then
        cp "$ENV_BACKUP" "$SCRIPT_DIR/.env"
        rm -f "$ENV_BACKUP"
        log_success ".env restored"
    else
        log_info "No .env backup to restore"
    fi
    
    log_step "[7/8] Running installation..."
    bash "$INSTALL_NEW"
    install_status=$?
    
    rm -f "$INSTALL_NEW"
    
    if [ $install_status -eq 0 ]; then
        log_step "[8/8] Verifying installation..."
        if verify_installation; then
            rm -f "$TEMP_SCRIPT_SELF" 2>/dev/null || true
            echo "=========================================="
            log_step "=== Update completed successfully! ==="
            echo "=========================================="
            log_info "Backup of previous version saved in: $BACKUP_DIR"
            log_info "You can remove it manually if everything works correctly"
            exit 0
        else
            log_error "Installation verification failed"
            rm -f "$TEMP_SCRIPT_SELF" 2>/dev/null || true
            echo "=========================================="
            log_error "=== Update verification failed ==="
            echo "=========================================="
            log_info "Previous version backup available in: $BACKUP_DIR"
            exit 1
        fi
    else
        rm -f "$TEMP_SCRIPT_SELF" 2>/dev/null || true
        echo "=========================================="
        log_error "Update installation failed with exit code $install_status"
        echo "=========================================="
        log_info "Previous version backup available in: $BACKUP_DIR"
        exit $install_status
    fi
else
    log_error "Failed to download install script from $INSTALL_SCRIPT_URL after retries"
    
    if [ -f "$ENV_BACKUP" ]; then
        log_info "Restoring .env file..."
        cp "$ENV_BACKUP" "$SCRIPT_DIR/.env"
        rm -f "$ENV_BACKUP"
        log_success ".env restored"
    fi
    
    rm -f "$TEMP_SCRIPT_SELF" 2>/dev/null || true
    
    echo "=========================================="
    log_error "=== Update failed ==="
    echo "=========================================="
    log_info "Previous version backup available in: $BACKUP_DIR"
    exit 1
fi
UPDATE_SCRIPT_EOF
        
        chmod +x "$temp_update_script"
        
        log_message "INFO" "Running clean update (removing old files and installing new version)..."
        bash "$temp_update_script"
        local install_status=$?
        
        rm -f "$temp_update_script"
        
        if [ $install_status -eq 0 ]; then
            log_message "SUCCESS" "Update installed successfully!"
            send_telegram_notification "<b>Update Installed Successfully!</b>

Version <code>$new_version</code> has been installed and the service has been restarted."
        else
            log_message "ERROR" "Update installation failed with exit code $install_status"
            send_telegram_notification "<b>Update Installation Failed!</b>

Failed to install version <code>$new_version</code>.

Please check logs: <code>sudo journalctl -u reset-password-api-dokploy -n 50</code>"
        fi
    else
        log_message "INFO" "AUTO_UPDATE is disabled. Sending notification only..."
        
        notification="$notification

<b>Auto-update disabled</b>

To enable automatic updates, set in <code>.env</code>:
<code>AUTOMATICALLY_CHECK_FOR_NEW_UPDATES=true</code>

To install manually, run:
<code>curl -sSL https://raw.coonlink.com/cloud/dokploy-reset-password/install.sh | bash</code>"
        
        send_telegram_notification "$notification"
    fi
    
    rm -f "$version_file"
    return 0
}

main() {
    mkdir -p "$SCRIPT_DIR"
    
    touch "$LOG_FILE"
    
    log_message "INFO" "=== Update Check Started ==="
    
    check_for_updates
    
    log_message "INFO" "=== Update Check Completed ==="
    echo ""
}

main "$@"
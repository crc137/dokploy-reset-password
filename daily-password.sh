#!/bin/bash

SCRIPT_DIR_THIS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_THIS/config.sh" ]; then
    source "$SCRIPT_DIR_THIS/config.sh"
elif [ -f "/root/ResetPasswordDeploy/config.sh" ]; then
    source "/root/ResetPasswordDeploy/config.sh"
else
    SCRIPT_DIR="/root/ResetPasswordDeploy"
    API_PORT="11292"
    SERVICE_NAME="reset-password-api-dokploy"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    RED="\033[0;31m"
    NC="\033[0m"
fi

STATE_FILE="$SCRIPT_DIR/tg_password_message_id"
LOG_FILE="$SCRIPT_DIR/password.log"

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

tg_escape_html() {
    local s="$1"
    local e_amp e_lt e_gt
    e_amp=$(printf '%s%s' '&' 'amp;')
    e_lt=$(printf '%s%s' '&' 'lt;')
    e_gt=$(printf '%s%s' '&' 'gt;')
    s=${s//'&'/"$e_amp"}
    s=${s//'<'/"$e_lt"}
    s=${s//'>'/"$e_gt"}
    printf '%s' "$s"
}

tg_send() {
    local text="$1"
    local response
    response=$(curl -s -m 30 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_ADMIN}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" 2>&1) || true
    if printf '%s' "$response" | grep -q '"ok":true'; then
        printf '%s' "$response" | grep -oE '"message_id":[0-9]+' | head -1 | grep -oE '[0-9]+'
        return 0
    fi
    log_message "ERROR" "Telegram sendMessage failed: $response"
    return 1
}

tg_edit() {
    local message_id="$1"
    local text="$2"
    local response
    response=$(curl -s -m 30 -X POST "https://api.telegram.org/bot${TG_TOKEN}/editMessageText" \
        -d "chat_id=${TG_ADMIN}" \
        -d "message_id=${message_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" 2>&1) || true
    if printf '%s' "$response" | grep -q '"ok":true'; then
        return 0
    fi
    log_message "WARNING" "Telegram editMessageText failed (message_id=${message_id}): $response"
    return 1
}

tg_notify() {
    local text="$1"
    local message_id=""
    if [ -f "$STATE_FILE" ]; then
        message_id=$(tr -dc '0-9' < "$STATE_FILE" 2>/dev/null)
    fi

    if [ -n "$message_id" ] && tg_edit "$message_id" "$text"; then
        log_message "INFO" "Telegram message ${message_id} edited"
        return 0
    fi

    local new_id
    new_id=$(tg_send "$text") || return 1
    if [ -n "$new_id" ]; then
        printf '%s\n' "$new_id" > "$STATE_FILE"
        chmod 600 "$STATE_FILE" 2>/dev/null || true
        log_message "SUCCESS" "Telegram message sent (message_id=${new_id}, saved for future edits)"
    fi
}

main() {
    mkdir -p "$SCRIPT_DIR"
    touch "$LOG_FILE"

    log_message "INFO" "=== Daily password reset started ==="

    local env_file="$SCRIPT_DIR/.env"
    if [ ! -f "$env_file" ]; then
        log_message "ERROR" ".env file not found at ${env_file}"
        exit 1
    fi

    set -a
    source "$env_file" 2>/dev/null
    set +a

    local daily_enabled="${TG_DAILY_PASSWORD:-true}"
    case "$daily_enabled" in
        true|1|yes|on) ;;
        *)
            log_message "INFO" "TG_DAILY_PASSWORD is disabled in .env - skipping"
            exit 0
            ;;
    esac

    if [ -z "${TG_TOKEN:-}" ] || [ -z "${TG_ADMIN:-}" ]; then
        log_message "WARNING" "TG_TOKEN or TG_ADMIN not set in .env - cannot notify"
        exit 1
    fi
    if [ -z "${API_KEY:-}" ]; then
        log_message "ERROR" "API_KEY not set in .env - cannot call the reset API"
        exit 1
    fi

    API_PORT="${API_PORT:-11292}"

    log_message "INFO" "Requesting password reset via API (auto mode)..."
    local response
    response=$(curl -s -m 60 -X POST "http://127.0.0.1:${API_PORT}/api/v1/reset-password" \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: ${API_KEY}" \
        -d '{"auto_mode": true}' 2>&1) || true

    if printf '%s' "$response" | grep -q '"success": *true'; then
        local password container_id now text
        password=$(printf '%s' "$response" | grep -oE '"password":\s*"[^"]*"' | head -1 | sed 's/.*"password":\s*"\([^"]*\)".*/\1/')
        container_id=$(printf '%s' "$response" | grep -oE '"container_id":\s*"[^"]*"' | head -1 | sed 's/.*"container_id":\s*"\([^"]*\)".*/\1/')
        if [ -z "$password" ]; then
            log_message "ERROR" "API returned success but password could not be parsed: $response"
            exit 1
        fi
        log_message "SUCCESS" "Password reset OK (container: ${container_id:-unknown})"

        now=$(date '+%Y-%m-%d %H:%M:%S %Z')
        text="<b>Dokploy Admin Password</b>

Updated: <code>$(tg_escape_html "$now")</code>
Container: <code>$(tg_escape_html "${container_id:-unknown}")</code>

Password: <code>$(tg_escape_html "$password")</code>

<i>This message is edited daily - keep it pinned.</i>"
        tg_notify "$text"
    else
        local now err text
        log_message "ERROR" "Password reset failed: $response"
        now=$(date '+%Y-%m-%d %H:%M:%S %Z')
        err=$(printf '%s' "$response" | grep -oE '"error":\s*"[^"]*"' | head -1 | sed 's/.*"error":\s*"\([^"]*\)".*/\1/')
        text="<b>Dokploy password reset FAILED</b>

Time: <code>$(tg_escape_html "$now")</code>
Error: <code>$(tg_escape_html "${err:-unknown}")</code>

Check: sudo journalctl -u ${SERVICE_NAME} -n 50"
        tg_notify "$text"
        exit 1
    fi

    log_message "INFO" "=== Daily password reset completed ==="
}

main "$@"
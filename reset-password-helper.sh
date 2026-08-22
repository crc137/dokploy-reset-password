#!/bin/bash
set -u -o pipefail

CONTAINER_ID="${1:-}"

if [[ -z "$CONTAINER_ID" ]]; then
    echo "Error: Container ID not provided"
    exit 1
fi

# Belt-and-suspenders: api_server.py already validates container_id against
# Docker's own container-name character rule before invoking this script,
# but this script can also be run directly, so it re-validates here too.
# `--` forces everything after it to be treated as positional CONTAINER,
# never as a docker exec flag, regardless of what CONTAINER_ID contains.
if ! [[ "$CONTAINER_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$ ]]; then
    echo "Error: Invalid container ID format"
    exit 1
fi

if RESULT=$(docker exec -- "$CONTAINER_ID" bash -c "pnpm run reset-password" 2>&1); then
    PASSWORD=$(echo "$RESULT" | grep -oE 'password:\s*(.+)' | sed -E 's/password:\s*(.+)/\1/' | head -1 | tr -d '[:space:]')
    if [[ -n "$PASSWORD" ]]; then
        echo "New password: ${PASSWORD}"
        exit 0
    else
        echo "Error: Could not parse password from output"
        echo "Output: ${RESULT}"
        exit 1
    fi
else
    echo "Error: Failed to reset password"
    echo "Output: ${RESULT}"
    exit 1
fi
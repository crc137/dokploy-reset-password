#!/bin/bash

CONTAINER_ID="${1}"

if [[ -z "$CONTAINER_ID" ]]; then
    echo "Error: Container ID not provided"
    exit 1
fi

RESULT=$(docker exec "$CONTAINER_ID" bash -c "pnpm run reset-password" 2>&1)

if [[ $? -eq 0 ]]; then
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
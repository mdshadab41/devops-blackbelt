#!/bin/bash
set -e

LOG_DIR="$HOME/app-logs"
LOG_FILE="$LOG_DIR/app.log"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: $LOG_FILE does not exist, nothing to rotate"
    exit 1
fi

mv "$LOG_FILE" "$LOG_FILE.$TIMESTAMP"
touch "$LOG_FILE"
find "$LOG_DIR" -name "app.log.*" -mtime "+$RETENTION_DAYS" -delete

echo "Log rotated successfully: $LOG_FILE.$TIMESTAMP"


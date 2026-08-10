#!/bin/bash
set -e

log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
}

TEMP_FILE=$(mktemp)

cleanup() {

    log "INFO" "Running cleanup..."
    rm -f "$TEMP_FILE"
    log "INFO" "Removed temp file: $TEMP_FILE"

}



trap cleanup EXIT

# argument validation

if [ -z "$1" ]; then
    log "ERROR" "Missing required argument: target name"
    log "ERROR" "Usage: $0 <target-name>"
    exit 1
fi

TARGET_NAME="$1"


log "INFO" "Script started for target: $TARGET_NAME"
echo "some data" > "$TEMP_FILE"
log "INFO" "Wrote data to temp file"
log "INFO" "Script completed successfully"



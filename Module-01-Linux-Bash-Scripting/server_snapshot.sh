#!/bin/bash
set -e

LOG_FILE="$HOME/server_snapshot.log"
DISK_WARN=70
DISK_CRIT=90
MEM_WARN=70
MEM_CRIT=90

STATUS=0

log() {
  local level="$1"
  shift
  local msg="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

# --- Argument validation ---
if [ -z "$1" ]; then
  echo "Usage: $0 <process-name>"
  echo "Example: $0 sshd"
  exit 1
fi

PROCESS_NAME="$1"

log "INFO" "===== Server Snapshot Started ====="

# --- Disk Check ---
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -ge "$DISK_CRIT" ]; then
  log "CRITICAL" "Disk usage is ${DISK_USAGE}%"
  STATUS=2
elif [ "$DISK_USAGE" -ge "$DISK_WARN" ]; then
  log "WARNING" "Disk usage is ${DISK_USAGE}%"
  [ "$STATUS" -lt 1 ] && STATUS=1
else
  log "INFO" "Disk usage OK (${DISK_USAGE}%)"
fi

# --- Memory Check ---
read TOTAL AVAILABLE <<< "$(free -m | awk 'NR==2 {print $2, $7}')"
MEM_USAGE=$(( (TOTAL - AVAILABLE) * 100 / TOTAL ))
if [ "$MEM_USAGE" -ge "$MEM_CRIT" ]; then
  log "CRITICAL" "Memory usage is ${MEM_USAGE}%"
  STATUS=2
elif [ "$MEM_USAGE" -ge "$MEM_WARN" ]; then
  log "WARNING" "Memory usage is ${MEM_USAGE}%"
  [ "$STATUS" -lt 1 ] && STATUS=1
else
  log "INFO" "Memory usage OK (${MEM_USAGE}%)"
fi

# --- Process Check --
if pgrep -f "$PROCESS_NAME" > /dev/null; then
  log "INFO" "Process '$PROCESS_NAME' is running"
else
  log "CRITICAL" "Process '$PROCESS_NAME' is NOT running"
  STATUS=2
fi
log "INFO" "===== Snapshot Complete — Overall Status: $STATUS ====="

exit $STATUS

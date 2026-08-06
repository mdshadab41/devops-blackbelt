#!/bin/bash

STATUS=0
# --- Disk Usage ---
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$DISK_USAGE" -ge 90 ]; then
    echo "CRITICAL: Disk usage is ${DISK_USAGE}%"
    STATUS=2
elif [ "$DISK_USAGE" -ge 70 ]; then 
    echo "WARNING: Disk usage is ${DISK_USAGE}%" 
    if [ "$STATUS" -lt 1 ]; then
       STATUS=1
    fi
else
    echo "OK: Disk usage is ${DISK_USAGE}%"
fi

# --- Memory Check ---
read TOTAL AVAILABLE <<< "$(free -m | awk 'NR==2 {print $2, $7}')"
MEM_USAGE=$(( (TOTAL - AVAILABLE) * 100 / TOTAL ))

if [ "$MEM_USAGE" -ge 90 ]; then
  echo "CRITICAL: Memory usage is ${MEM_USAGE}%"
  STATUS=2
elif [ "$MEM_USAGE" -ge 70 ]; then
  echo "WARNING: Memory usage is ${MEM_USAGE}%"
  if [ "$STATUS" -lt 1 ]; then
    STATUS=1
  fi
else
  echo "OK: Memory usage is ${MEM_USAGE}%"
fi

if pgrep sshd > /dev/null; then
    echo "OK: sshd is running"
else
    echo "CRITICAL: sshd is not running"
    STATUS=2
fi




echo "Overall status code: $STATUS"
exit $STATUS

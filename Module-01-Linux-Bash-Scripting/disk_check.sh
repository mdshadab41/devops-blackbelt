USAGE=$(df / | awk  'NR==2 {print $5}' | tr -d '%')

if ! [[ "$USAGE" =~ ^[0-9]+$ ]]; then 
  echo "ERROR: could not determine disk usage"
  exit 2
fi

if [ "$USAGE" -ge 30 ]; then
   echo "WARNING: Disk usage is $USAGE% (threshold: 30%)"
   exit 1
else
    echo "Okay: Disk usage is $USAGE% (threshold: 30%)"
    exit 0

fi

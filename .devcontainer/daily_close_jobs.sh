#!/bin/bash
# Script to run close_jobs_by_end_date() once per day at 00:01

# Infinite loop
while true; do
  # Get current hour and minute in 24h format
  CURRENT_TIME=$(date +%H%M)

  if [ "$CURRENT_TIME" = "0001" ]; then
    echo "$(date): Running close_jobs_by_end_date()"
    psql -U nullandvoid -d void -c "SELECT close_jobs_by_end_date();"
    
    # Sleep 61 seconds to avoid multiple executions within the same minute
    sleep 61
  else
    # Sleep 30 seconds before checking the time again
    sleep 30
  fi
done

#!/bin/sh
# Clean recordings older than 7 days
/usr/bin/find /var/spool/asterisk/monitor -name "*.wav" -mtime +7 -delete 2>/dev/null
# Log
echo "[$(date)] Cleaned recordings older than 7 days from /var/spool/asterisk/monitor" >> /var/log/asterisk-recordings-cleanup.log

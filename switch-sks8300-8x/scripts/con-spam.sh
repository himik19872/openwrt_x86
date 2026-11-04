#!/bin/sh
# спам Ctrl+B (0x02) в консоль в течение N секунд
N=${1:-20}
i=0
while [ "$i" -lt "$N" ]; do
  printf "\002\002\002\002" | socat -u - FILE:/dev/ttyUSB0,b9600,raw,echo=0 2>/dev/null
  sleep 0.2
  i=$((i+1))
done

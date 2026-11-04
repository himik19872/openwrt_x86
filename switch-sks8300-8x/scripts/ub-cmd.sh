#!/bin/sh
P=/dev/ttyUSB0
CMD="$1"
WAIT=${2:-3}
stty -F $P 9600 cs8 -cstopb -parenb -crtscts clocal cread raw -echo -ixon -ixoff -hupcl
cat $P > /tmp/ubc.out 2>/dev/null &
CP=$!
sleep 0.3
i=1
L=${#CMD}
while [ $i -le $L ]; do
  ch=$(printf "%s" "$CMD" | cut -c$i)
  printf "%s" "$ch" > $P
  sleep 0.07
  i=$((i+1))
done
printf "\r" > $P
sleep $WAIT
kill $CP 2>/dev/null

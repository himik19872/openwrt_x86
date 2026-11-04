#!/bin/sh
P=/dev/ttyUSB0
stty -F $P 9600 cs8 -cstopb -parenb -crtscts clocal cread raw -echo -ixon -ixoff -hupcl
# открыть один раз на чтение
cat $P > /tmp/ub.out 2>/dev/null &
CP=$!
sleep 1
printf "\006" > $P
sleep 1
for c in d i a g s h e l l _ u n i p o e _ e n v; do
  printf "%s" "$c" > $P
  sleep 0.15
done
printf "\r" > $P
sleep 4
kill $CP 2>/dev/null

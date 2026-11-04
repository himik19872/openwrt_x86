#!/bin/sh
# непрерывный лог консоли
exec socat -u FILE:/dev/ttyUSB0,b9600,raw,echo=0 - >> /tmp/con.log 2>/dev/null

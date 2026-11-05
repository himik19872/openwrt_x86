#!/bin/sh
# probe-bridges.sh — определить имя моста и посчитать записи FDB на каждом OpenWrt
KEY=/root/.ssh/id_ed25519
for ip in 192.168.1.54 192.168.1.120 192.168.1.244; do
	br=$(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$ip" \
		'for b in br-lan switch lan; do [ -d /sys/class/net/$b/bridge ] && echo $b && break; done' 2>/dev/null | tr -d '\r' | tail -1)
	if [ -z "$br" ]; then
		echo "$ip: МОСТ НЕ НАЙДЕН"
		continue
	fi
	cnt=$(ssh -i "$KEY" -o StrictHostKeyChecking=no "root@$ip" "bridge fdb show br $br | wc -l" 2>/dev/null | tr -d '\r')
	echo "$ip: мост=$br записей=$cnt"
done

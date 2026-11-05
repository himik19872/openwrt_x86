#!/bin/sh
# probe-fdb.sh — FDB через sysfs (без пакета bridge).
# /sys/class/net/<bridge>/brif/<port>/ — список портов моста.
# FDB берём из /sys/kernel/debug/bridge/ (если смонтирован) либо через brctl.

KEY=/root/.ssh/id_ed25519
SSHK="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5"

for ip in 192.168.1.54 192.168.1.120 192.168.1.244; do
	echo "=== $ip"
	ssh $SSHK "root@$ip" '
		br=""
		for b in br-lan switch lan; do
			[ -d /sys/class/net/$b/brif ] && br=$b && break
		done
		[ -z "$br" ] && { echo "  моста нет"; exit 0; }
		echo "  мост: $br"
		echo "  порты: $(ls /sys/class/net/$br/brif | tr "\n" " ")"
		# мак-таблица: на DSA-коммутаторах это fdb железа, читаем через debugfs
		if [ -r /sys/kernel/debug/bridge/$br/fdb ]; then
			echo "  debugfs FDB:"; cat /sys/kernel/debug/bridge/$br/fdb | head -3
		else
			echo "  debugfs нет; есть brctl: $(command -v brctl || echo нет)"
		fi
		# альтернатива: ip neigh + /proc/net/arp
		echo "  arp: $(wc -l < /proc/net/arp) строк"
	' 2>&1 | grep -v "hostkey"
done

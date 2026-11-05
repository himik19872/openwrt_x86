#!/bin/sh
# collect.sh — сбор сырых данных о сети с управляемых устройств.
# Запускается на роутере 192.168.1.1 (там есть nc, arp-scan, ssh-ключ к OpenWrt).
# Результат: /root/netmap/*.txt — таблицы MAC, LLDP и ARP.

OUT=/root/netmap
mkdir -p "$OUT"

ELTEX=192.168.1.245
ELTEX_USER=admin
ELTEX_PASS=admin
DLINK=192.168.1.108
DLINK_USER=admin
DLINK_PASS=96811621q
OWRTS="192.168.1.54 192.168.1.120 192.168.1.244"
SSHK="-i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no"

# --- netcat-сессия: логин, команда, пролистывание страниц, выход
telnet_cmd() { # $1=host $2=user $3=pass $4=command $5=pages
	host=$1; user=$2; pass=$3; cmd=$4; pages=${5:-8}
	(
		printf "%s\r\n" "$user"; sleep 1
		printf "%s\r\n" "$pass"; sleep 3
		printf "%s\r\n" "$cmd"; sleep 3
		i=0
		while [ $i -lt "$pages" ]; do printf " "; sleep 1; i=$((i + 1)); done
		printf "\r\n"; sleep 1
		printf "exit\r\n"; sleep 1
	) | nc "$host" 23 | tr -cd '\11\12\15\40-\176' | tr -d '\r' | sed 's/\[K//g'
}

echo "[1/4] ARP-скан подсетей..."
arp-scan -I br-lan --retry=2 --timeout=400 192.168.1.0/24 >/dev/null 2>&1
arp-scan -I br-lan --retry=2 --timeout=400 192.168.2.0/24 >/dev/null 2>&1
awk 'NR > 1 && $4 != "00:00:00:00:00:00" { print $1, $4 }' /proc/net/arp | sort -u >"$OUT/arp.txt"

echo "[2/4] Eltex $ELTEX..."
telnet_cmd "$ELTEX" "$ELTEX_USER" "$ELTEX_PASS" "show mac vlan 1" 8 >"$OUT/eltex-mac.txt"
telnet_cmd "$ELTEX" "$ELTEX_USER" "$ELTEX_PASS" "show lldp neighbors" 4 >"$OUT/eltex-lldp.txt"

echo "[3/4] D-Link $DLINK..."
telnet_cmd "$DLINK" "$DLINK_USER" "$DLINK_PASS" "show fdb" 8 >"$OUT/dlink-mac.txt"
telnet_cmd "$DLINK" "$DLINK_USER" "$DLINK_PASS" "show lldp remote_ports" 8 >"$OUT/dlink-lldp.txt"

echo "[4/4] OpenWrt..."
for ip in $OWRTS; do
	# мост может называться br-lan (x86/обычные) или switch (DSA-коммутатор)
	ssh $SSHK "root@$ip" '
		for b in br-lan switch; do
			[ -d /sys/class/net/$b/bridge ] && echo "$b" && break
		done' 2>/dev/null | tail -1 >"$OUT/.br"
	br=$(cat "$OUT/.br")
	[ -n "$br" ] || { echo "  ! $ip: мост не найден"; continue; }
	ssh $SSHK "root@$ip" "bridge fdb show br $br" 2>/dev/null >"$OUT/owrt-$ip-fdb.txt"
	ssh $SSHK "root@$ip" 'lldpcli show neighbors' 2>/dev/null >"$OUT/owrt-$ip-lldp.txt"
	echo "  $ip: мост $br, FDB $(grep -c . "$OUT/owrt-$ip-fdb.txt") строк"
done
rm -f "$OUT/.br"

echo "готово: файлы в $OUT"
wc -l "$OUT"/*.txt 2>/dev/null | tail -15

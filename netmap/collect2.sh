#!/bin/sh
# collect2.sh — сбор данных о сети с управляемых устройств (запуск на 192.168.1.1).
# Итог: /root/netmap/{arp,eltex-mac,eltex-lldp,dlink-mac,owrt-<ip>-mac}.txt

OUT=/root/netmap
mkdir -p "$OUT"

ELTEX=192.168.1.245
ELTEX_USER=admin
ELTEX_PASS=admin
DLINK=192.168.1.108
DLINK_USER=admin
DLINK_PASS=96811621q
OWRTS="192.168.1.54 192.168.1.120 192.168.1.244"
KEY=/root/.ssh/id_ed25519

# telnet-сессия через nc (на роутере нет telnet-клиента)
telnet_cmd() { # $1=host $2=user $3=pass $4=cmd $5=страниц
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

echo "[1/4] ARP-скан..."
arp-scan -I br-lan --retry=2 --timeout=400 192.168.1.0/24 >/dev/null 2>&1
arp-scan -I br-lan --retry=2 --timeout=400 192.168.2.0/24 >/dev/null 2>&1
awk 'NR > 1 && $4 != "00:00:00:00:00:00" { print $1, tolower($4) }' /proc/net/arp | sort -u >"$OUT/arp.txt"
echo "  хостов в ARP: $(wc -l <"$OUT/arp.txt")"

echo "[2/4] Eltex $ELTEX..."
telnet_cmd "$ELTEX" "$ELTEX_USER" "$ELTEX_PASS" "show mac vlan 1" 8 >"$OUT/eltex-mac.txt"
telnet_cmd "$ELTEX" "$ELTEX_USER" "$ELTEX_PASS" "show lldp neighbors" 4 >"$OUT/eltex-lldp.txt"
echo "  MAC-записей: $(grep -cE '^1 +[0-9a-f]{2}:' "$OUT/eltex-mac.txt")"

echo "[3/4] D-Link $DLINK..."
telnet_cmd "$DLINK" "$DLINK_USER" "$DLINK_PASS" "show fdb" 8 >"$OUT/dlink-mac.txt"
telnet_cmd "$DLINK" "$DLINK_USER" "$DLINK_PASS" "show lldp remote_ports" 8 >"$OUT/dlink-lldp.txt"
echo "  MAC-записей: $(grep -cE '^ *1 +default' "$OUT/dlink-mac.txt")"

echo "[4/4] OpenWrt (brctl showmacs)..."
for ip in $OWRTS; do
	ssh -i "$KEY" -o StrictHostKeyChecking=no "root@$ip" '
		for b in br-lan switch lan; do
			[ -d /sys/class/net/$b/brif ] || continue
			echo "##BRIDGE $b"
			brctl showmacs "$b" 2>/dev/null
			break
		done' 2>/dev/null | tr -d '\r' >"$OUT/owrt-$ip-mac.txt"
	echo "  $ip: $(grep -cE '^ *[0-9]+ +([0-9a-f]{2}:){5}' "$OUT/owrt-$ip-mac.txt") записей"
done

echo "готово. Файлы в $OUT/"

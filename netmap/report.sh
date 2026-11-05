#!/bin/sh
# report.sh — сводная карта: MAC → IP → устройство → коммутатор/порт.
# Читает файлы из /root/netmap (результат collect2.sh).

cd /root/netmap || exit 1
OUT=/root/netmap/report.txt

# ---------- 1. FDB всех коммутаторов в один список: mac;host;port ----------
: > fdb-all.txt

# Eltex: "1      00:02:c9:56:c8:ca   Learnt      te 0/2"
grep -E '^1 +[0-9a-f]{2}:' eltex-mac.txt |
	awk '{ p=""; for(i=NF-1;i<=NF;i++) p = p (i==NF-1?"":" ") $i; print tolower($2) ";245;" p }' >> fdb-all.txt

# D-Link: "1    default    DC-32-62-81-35-A4 5    Dynamic"
grep -E '^ *1 +default' dlink-mac.txt |
	awk '{ m=tolower($3); gsub(/-/,":",m); print m ";108;" $4 }' >> fdb-all.txt

# OpenWrt: "  4     00:02:c9:57:18:ec       no     19.37"  (порт = номер ifindex-порта)
for f in owrt-*-mac.txt; do
	[ -f "$f" ] || continue
	ip=$(echo "$f" | sed 's/owrt-\(.*\)-mac.txt/\1/' | awk -F. '{print $NF}')
	br=$(grep '^##BRIDGE' "$f" | awk '{print $2}')
	[ -n "$br" ] || continue
	# сопоставляем номер порта brctl с именем интерфейса
	ports=$(grep '^##PORTS' "$f" | cut -d' ' -f2-)
	grep -E '^ *[0-9]+ +([0-9a-f]{2}:){5}' "$f" |
		awk -v h="$ip" -v n=$(echo "$br" | wc -c) '{print tolower($2) ";" h ";" "port" $1}' >> fdb-all.txt
done

sort -u fdb-all.txt -o fdb-all.txt

# ---------- 2. ARP: mac → ip ----------
awk '{print $2, $1}' arp.txt | sort -u > arp-by-mac.txt

# ---------- 3. Сводка ----------
{
	echo "IP               MAC                коммутатор   порт"
	echo "---------------- ------------------ ------------ -------"
	while read -r mac host port; do
		ip=$(grep -m1 "^$mac " arp-by-mac.txt | awk '{print $2}')
		[ -n "$ip" ] || ip="-"
		printf "%-16s %-18s %-12s %s\n" "$ip" "$mac" ".$host" "$port"
	done < fdb-all.txt | sort -k3,3 -k4,4
} > "$OUT"

echo "Отчёт: $OUT"
echo "Всего записей FDB: $(wc -l < fdb-all.txt)"
echo "С IP-адресом: $(awk '$1 != "-"' "$OUT" | grep -cE '^[0-9]')"
echo
head -30 "$OUT"

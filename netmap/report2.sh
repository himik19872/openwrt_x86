#!/bin/sh
# report2.sh — сводная карта: MAC -> IP, коммутатор, порт.

cd /root/netmap || exit 1
OUT=/root/netmap/report.txt

# ---------- 1. FDB всех коммутаторов: "mac host port" ----------
: > fdb-all.txt

# Eltex: "1      00:02:c9:56:c8:ca   Learnt      te 0/2"
grep -E '^1 +[0-9a-f]{2}:' eltex-mac.txt |
	sed -E 's/^\s*1\s+([0-9a-fA-F:]{17})\s+\w+\s+(.*)$/\1 \2/' |
	awk '{ p=$2; if (NF>2) p=$2" "$3; print tolower($1) " 245 " p }' >> fdb-all.txt

# D-Link: "1    default    DC-32-62-81-35-A4 5    Dynamic"
grep -E '^ *1 +default' dlink-mac.txt |
	awk '{ m=tolower($3); gsub(/-/,":",m); print m " 108 gi" $4 }' >> fdb-all.txt

# OpenWrt: строки вида "  4     00:02:c9:57:18:ec       no     19.37"
for f in owrt-*-mac.txt; do
	[ -f "$f" ] || continue
	ip=$(echo "$f" | sed 's/owrt-\(.*\)-mac.txt/\1/' | awk -F. '{print $NF}')
	grep -E '^ *[0-9]+ +([0-9a-f]{2}:){5}' "$f" |
		awk -v h="$ip" '{ print tolower($2) " " h " port" $1 }' >> fdb-all.txt
done

sort -u fdb-all.txt -o fdb-all.txt

# ---------- 2. ARP: mac -> ip ----------
awk '{ print tolower($2) " " $1 }' arp.txt | sort -u > arp-by-mac.txt

# ---------- 3. Отчёт ----------
{
	printf "%-16s %-18s %-6s %s\n" "IP" "MAC" "свитч" "порт"
	printf "%-16s %-18s %-6s %s\n" "----------------" "------------------" "------" "--------"
	while read -r mac host port; do
		ip=$(awk -v m="$mac" '$1 == m { print $2; exit }' arp-by-mac.txt)
		[ -n "$ip" ] || ip="?"
		printf "%-16s %-18s %-6s %s\n" "$ip" "$mac" ".$host" "$port"
	done < fdb-all.txt | sort -k1,1 -k3,3
} >"$OUT"

echo "Отчёт: $OUT"
echo "Записей FDB: $(wc -l < fdb-all.txt)"
echo "С IP-адресом: $(grep -cE '^[0-9]' "$OUT")"

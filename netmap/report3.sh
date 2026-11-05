#!/bin/sh
# report3.sh — сводная карта: MAC -> IP, коммутатор, порт (с именами интерфейсов).

cd /root/netmap || exit 1
OUT=/root/netmap/report.txt

: > fdb-all.txt

# ---------- Eltex: "1  MAC  Learnt  te 0/2" ----------
grep -E '^1 +[0-9a-f]{2}:' eltex-mac.txt |
	awk '{ p=$4; if (NF >= 5) p=$4" "$5; printf "%s 245 %s\n", tolower($2), p }' >> fdb-all.txt

# ---------- D-Link: "1  default  DC-32-62-81-35-A4 5  Dynamic" ----------
grep -E '^ *1 +default' dlink-mac.txt |
	awk '{ m=tolower($3); gsub(/-/,":",m); printf "%s 108 gi%s\n", m, $4 }' >> fdb-all.txt

# ---------- OpenWrt: "  4  00:02:..  no  19.37" ----------
for f in owrt-*-mac.txt; do
	[ -f "$f" ] || continue
	h=$(echo "$f" | sed 's/owrt-\(.*\)-mac.txt/\1/' | awk -F. '{print $NF}')
	# имена интерфейсов по порядку = порядок портов brctl (1=первый в brif)
	ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no "root@192.168.1.$h" \
		'for b in br-lan switch lan; do [ -d /sys/class/net/$b/brif ] && { ls /sys/class/net/$b/brif | tr "\n" " "; break; }; done' \
		2>/dev/null | tr -d '\r' >"/tmp/ports-$h.txt"
	awk -v h="$h" '{
		n = $1 + 0; mac = tolower($2); port = "port" n
		printf "%s %s %s\n", mac, h, port
	}' "$f" | grep -E '^([0-9a-f]{2}:){5}' >> fdb-all.txt
done

sort -u fdb-all.txt -o fdb-all.txt

# ---------- ARP ----------
awk '{ print tolower($2) " " $1 }' arp.txt | sort -u > arp-by-mac.txt

# ---------- Отчёт ----------
{
	printf "%-16s %-18s %-6s %-10s %s\n" "IP" "MAC" "свитч" "порт" "имя порта"
	printf "%-16s %-18s %-6s %-10s %s\n" "----------------" "------------------" "-----" "---------" "---------"
	while read -r mac host port; do
		ip=$(awk -v m="$mac" '$1 == m { print $2; exit }' arp-by-mac.txt)
		[ -n "$ip" ] || ip="?"
		name=$port
		case "$port" in
		port*)
			idx=${port#port}
			fn="/tmp/ports-$host.txt"
			[ -f "$fn" ] && name=$(awk -v i="$idx" '{ print $i }' "$fn")
			;;
		esac
		printf "%-16s %-18s %-6s %-10s %s\n" "$ip" "$mac" ".$host" "$port" "$name"
	done < fdb-all.txt | sort -k3,3 -k4,4V
} >"$OUT"

echo "Отчёт: $OUT   записей: $(wc -l < fdb-all.txt)"

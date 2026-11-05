#!/bin/sh
# tree.sh — построение дерева топологии и выявление «за коммутатором».
#
# Логика: если на порту коммутатора видно много MAC, а один из них принадлежит
# известному коммутатору — это uplink. Устройства, чьи MAC видны на других
# коммутаторах, но не на этом порту, находятся «глубже».
#
# Ключевой факт домена: все коммутаторы плоские (один VLAN), FDB везде учит все
# MAC, поэтому «глубину» определяем по минимальному числу MAC на порту = точка
# входа устройства.

cd /root/netmap || exit 1
R=report.txt

# известные инфраструктурные MAC (по данным ARP/портов)
INFRA="
d0:aa:5f:01:8d:23:.54 sw10g OpenWrt RTL9303
04:ba:d6:3c:50:a0:.108 D-Link DGS-1210-10
cc:9d:a2:45:f1:c0:.245 Eltex core
50:4f:3b:b7:fd:b8:.244 OpenWrt3
50:ff:20:58:8b:b6:.120 OpenWrt2
5c:15:c5:0c:26:2d:.110 PoE switch
5c:15:c5:0d:7e:6a:.133 PoE switch
5c:15:c5:0e:1a:b7:.46 PoE switch
dc:32:62:81:35:a4:.116 PoE switch
dc:32:62:81:35:f2:.126 PoE switch
1c:fd:08:7b:a0:08:.1 router (LAN)
"

echo "════════════════════════════════════════════════════════════"
echo " ТОПОЛОГИЯ СЕТИ 192.168.1.0/24"
echo "════════════════════════════════════════════════════════════"
echo

echo "── ИНФРАСТРУКТУРА ──────────────────────────────────────────"
echo "$INFRA" | grep -v '^$' | while read -r mac host name rest; do
	line=$(grep -i "^[^ ]* *$mac " "$R" | awk '$3 != "."host-1' | head -1)
	ip=$(grep -i "$mac" "$R" | awk '{print $1; exit}')
	printf "  %-16s %-18s %-22s %s\n" "${ip:--}" "$mac" "$name" "$rest"
done
echo

echo "── СВЯЗИ МЕЖДУ КОММУТАТОРАМИ ───────────────────────────────"
echo " (порт, где виден MAC соседнего коммутатора)"

# .245 -> соседи
for m in 04:ba:d6:3c:50:a0 d0:aa:5f:01:8d:23 50:4f:3b:b7:fd:b8; do
	row=$(awk -v m="$m" '$2 == m && $3 == ".245" { print $4" "$5 }' "$R" | head -1)
	[ -n "$row" ] && printf "  .245 (ядро)   %-24s -> %s\n" "$row" "$(echo "$INFRA" | grep -i "$m" | awk '{print $2" "$3}')"
done
# .108 -> соседи
for m in dc:32:62:81:35:a4 dc:32:62:81:35:f2 50:ff:20:58:8b:b6; do
	row=$(awk -v m="$m" '$2 == m && $3 == ".108" { print $4 }' "$R" | head -1)
	[ -n "$row" ] && printf "  .108 (D-Link) %-24s -> %s\n" "$row" "$(echo "$INFRA" | grep -i "$m" | awk '{print $2" "$3}')"
done
# .54 -> соседи
for m in 04:ba:d6:3c:50:a0 50:ff:20:58:8b:b6 50:4f:3b:b7:fd:b8 1c:fd:08:7b:a0:08; do
	row=$(awk -v m="$m" '$2 == m && $3 == ".54" { print $5 }' "$R" | head -1)
	[ -n "$row" ] && printf "  .54 (sw10g)   %-24s -> %s\n" "$row" "$(echo "$INFRA" | grep -i "$m" | awk '{print $2" "$3}')"
done
echo

echo "── УСТРОЙСТВА ПО КОММУТАТОРАМ ──────────────────────────────"
for sw in .245 .54 .108 .120 .244; do
	n=$(awk -v s="$sw" '$3 == s' "$R" | wc -l)
	echo
	echo "  ▼ коммутатор $sw  ($n записей)"
	awk -v s="$sw" '$3 == s { printf "     %-16s %-18s %s\n", $1, $2, ($5 ? $5 : $4) }' "$R" |
		sort -k3 | head -40
done

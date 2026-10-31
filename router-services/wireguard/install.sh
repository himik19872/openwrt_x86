#!/bin/sh
# Установка панели управления WireGuard-сервером
set -e
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== [1/4] Пакеты =="
apk add --no-cache wireguard-tools qrencode jq >/dev/null 2>&1 || true

echo "== [2/4] Файлы =="
mkdir -p /etc/wgadmin /www/wgadmin
cp -f "$DIR/files/usr/libexec/wgadmin-api" /usr/libexec/wgadmin-api
cp -f "$DIR/files/www/wgadmin/index.html" /www/wgadmin/index.html
chmod +x /usr/libexec/wgadmin-api
ln -sf /usr/libexec/wgadmin-api /www/cgi-bin/wgadmin

echo "== [3/4] Интерфейс wg0 =="
if ! uci -q get network.wg0 >/dev/null; then
	uci set network.wg0=interface
	uci set network.wg0.proto='wireguard'
	uci set network.wg0.private_key="$(wg genkey)"
	uci set network.wg0.listen_port='51820'
	uci add_list network.wg0.addresses='10.66.66.1/24'
	uci commit network
	echo "  создан интерфейс wg0 (10.66.66.1/24, UDP 51820)"
else
	echo "  wg0 уже существует — пропуск"
fi

if ! uci -q get firewall.wg >/dev/null; then
	uci set firewall.wg=zone
	uci set firewall.wg.name='wg'
	uci set firewall.wg.input='ACCEPT'
	uci set firewall.wg.output='ACCEPT'
	uci set firewall.wg.forward='ACCEPT'
	uci set firewall.wg.network='wg0'
	uci add firewall rule >/dev/null
	uci set firewall.@rule[-1].name='Allow-WireGuard'
	uci set firewall.@rule[-1].src='wan'
	uci set firewall.@rule[-1].proto='udp'
	uci set firewall.@rule[-1].dest_port='51820'
	uci set firewall.@rule[-1].target='ACCEPT'
	uci commit firewall
	echo "  создана зона firewall 'wg' и правило UDP 51820"
fi

echo "== [4/4] Применение =="
/etc/init.d/network reload >/dev/null 2>&1 || true
fw4 reload >/dev/null 2>&1 || true

echo
echo "Готово. Панель: http://<router>/wgadmin/  (логин root, пароль роутера)"
echo "Откройте панель и добавьте клиентов — конфиги .conf и QR-коды генерируются автоматически."

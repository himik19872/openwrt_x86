#!/bin/sh
# Установка панели управления поддоменами (DuckDNS + nginx + dnsmasq + wildcard TLS)
set -e
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== [1/5] Пакеты =="
apk add --no-cache jq curl openssl acme-acmesh >/dev/null 2>&1 || true

echo "== [2/5] Файлы =="
mkdir -p /etc/duckdns /etc/dnsmasq.d /www/dns
cp -f "$DIR/files/usr/libexec/duckdns-apply" /usr/libexec/duckdns-apply
cp -f "$DIR/files/usr/libexec/duckdns-sync" /usr/libexec/duckdns-sync
cp -f "$DIR/files/usr/libexec/duckdns-api" /usr/libexec/duckdns-api
cp -f "$DIR/files/usr/libexec/duckdns-ui" /usr/libexec/duckdns-ui
cp -f "$DIR/files/www/dns/index.html" /www/dns/index.html
chmod +x /usr/libexec/duckdns-*
ln -sf /usr/libexec/duckdns-api /www/cgi-bin/dnsadmin
ln -sf /usr/libexec/duckdns-ui /www/cgi-bin/dnsui

if [ -f /etc/duckdns/sites.json ]; then
	echo "  /etc/duckdns/sites.json уже существует — оставляю"
else
	cp -f "$DIR/files/etc/duckdns/sites.json" /etc/duckdns/sites.json
fi
[ -s /etc/duckdns/api.key ] || hexdump -n 16 -e '16/1 "%02x"' /dev/urandom > /etc/duckdns/api.key
chmod 600 /etc/duckdns/api.key

echo "== [3/5] dnsmasq confdir =="
uci set dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
uci commit dhcp

echo "== [4/5] Firewall: 443 на роутер =="
if uci show firewall | grep -q "name='Allow-DuckDNS-Web'"; then
	echo "  правило уже есть"
else
	uci add firewall rule >/dev/null
	uci set firewall.@rule[-1].name='Allow-DuckDNS-Web'
	uci set firewall.@rule[-1].src='wan'
	uci set firewall.@rule[-1].proto='tcp'
	uci set firewall.@rule[-1].dest_port='443'
	uci set firewall.@rule[-1].target='ACCEPT'
	uci commit firewall
fi

echo "== [5/5] Cron + применение =="
CRON=/etc/crontabs/root
grep -q duckdns-sync "$CRON" 2>/dev/null || echo "*/5 * * * * /usr/libexec/duckdns-sync >/dev/null 2>&1" >> "$CRON"
/etc/init.d/cron restart >/dev/null 2>&1 || true
fw4 reload >/dev/null 2>&1 || true

echo
echo "Осталось выпустить wildcard-сертификат (один раз):"
echo "  /usr/lib/acme/client/acme.sh --issue --server letsencrypt --dns dns_duckdns \\"
echo "      -d <domain> -d '*.<domain>' --home /etc/acme"
echo "  /usr/lib/acme/client/acme.sh --install-cert -d <domain> --ecc \\"
echo "      --key-file /etc/nginx/ssl/ha.key --fullchain-file /etc/nginx/ssl/ha.crt \\"
echo "      --reloadcmd '/etc/init.d/nginx reload' --home /etc/acme"
echo
echo "Токен DuckDNS берётся из /etc/acme/account.conf (DuckDNS_Token) или /etc/duckdns/token."
echo "Панель: http://<router>/cgi-bin/dnsui"

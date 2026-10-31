#!/bin/sh
# Общие компоненты: nginx, фикс hairpin NAT (br_netfilter), LuCI-карточки сервисов
set -e
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== [1/3] nginx =="
apk add --no-cache nginx-ssl >/dev/null 2>&1 || true
mkdir -p /etc/nginx/conf.d /etc/nginx/ssl
if [ -f /etc/nginx/nginx.conf ]; then
	cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak.$(date +%s)"
	echo "  существующий nginx.conf сохранён в .bak"
fi
cp -f "$DIR/files/etc/nginx/nginx.conf" /etc/nginx/nginx.conf

# подставляем реальный домен из конфига dns-domains (если он уже установлен)
DOMAIN=$(jq -r '.base // empty' /etc/duckdns/sites.json 2>/dev/null)
if [ -n "$DOMAIN" ]; then
	sed -i "s/himik1987\.duckdns\.org/$DOMAIN/g" /etc/nginx/nginx.conf /etc/nginx/conf.d/traccar.conf 2>/dev/null || true
	echo "  домен в конфигах: $DOMAIN"
fi
nginx -t >/dev/null 2>&1 && /etc/init.d/nginx reload >/dev/null 2>&1 || true

echo "== [2/3] Hairpin NAT / br_netfilter =="
# Docker (dockerd) тянет br_netfilter и включает bridge-nf-call-iptables=1,
# из-за чего fw4-reflection не делает SNAT и пробросы не работают из LAN.
if ! grep -q "bridge-nf-call-iptables=0" /etc/sysctl.conf 2>/dev/null; then
	{
		echo ""
		echo "# hairpin/DNAT on fw4: br_netfilter breaks reflection SNAT"
		echo "net.bridge.bridge-nf-call-iptables=0"
		echo "net.bridge.bridge-nf-call-ip6tables=0"
	} >> /etc/sysctl.conf
fi
sysctl -qw net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
sysctl -qw net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true

echo "== [3/3] LuCI: карточки сервисов =="
mkdir -p /usr/share/luci/menu.d /www/luci-static/resources/view
cp -f "$DIR/files/luci/menu.d/luci-app-webservices.json" /usr/share/luci/menu.d/
cp -f "$DIR/files/luci/menu.d/luci-app-traccar.json" /usr/share/luci/menu.d/
cp -f "$DIR/files/luci/view/webservices.js" /www/luci-static/resources/view/webservices.js
cp -f "$DIR/files/luci/view/traccar.js" /www/luci-static/resources/view/traccar.js
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd reload >/dev/null 2>&1 || true

echo
echo "Готово. Карточки сервисов: LuCI → меню «Сервисы»."
echo "Проверка hairpin: с LAN-клиента откройте http://<wan-ip>:<проброшенный-порт>"

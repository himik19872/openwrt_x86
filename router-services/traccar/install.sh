#!/bin/sh
# Установка Traccar (GPS-трекинг) в Docker с публикацией портов
set -e
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== [1/4] Docker =="
if ! command -v docker >/dev/null 2>&1; then
	echo "  Docker не установлен: apk add dockerd docker docker-compose"
	exit 1
fi
/etc/init.d/docker enable 2>/dev/null || true
/etc/init.d/docker start 2>/dev/null || true
sleep 3

echo "== [2/4] Контейнер =="
if docker ps -a --format '{{.Names}}' | grep -qx traccar; then
	echo "  контейнер traccar уже существует — пропуск (пересоздать: docker rm -f traccar)"
else
	docker run -d --name traccar --restart unless-stopped \
		-p 8082:8082 \
		-p 5000-5052:5000-5052/tcp -p 5000-5052:5000-5052/udp \
		-p 5055-5150:5055-5150/tcp -p 5055-5150:5055-5150/udp \
		-v traccar-logs:/opt/traccar/logs \
		-v traccar-data:/opt/traccar/data \
		traccar/traccar:latest
fi

echo "== [3/4] nginx (HTTPS-прокси) =="
mkdir -p /etc/nginx/conf.d
if [ -f /etc/nginx/conf.d/traccar.conf ]; then
	echo "  /etc/nginx/conf.d/traccar.conf уже есть — оставляю"
else
	cp -f "$DIR/files/etc/nginx/conf.d/traccar.conf" /etc/nginx/conf.d/traccar.conf
	DOMAIN=$(jq -r '.base // empty' /etc/duckdns/sites.json 2>/dev/null)
	[ -n "$DOMAIN" ] && sed -i "s/himik1987\.duckdns\.org/$DOMAIN/g" /etc/nginx/conf.d/traccar.conf
fi
nginx -t >/dev/null 2>&1 && /etc/init.d/nginx reload >/dev/null 2>&1 || true

echo "== [4/4] Firewall =="
if ! uci show firewall | grep -q "name='Allow-Traccar'"; then
	uci add firewall rule >/dev/null
	uci set firewall.@rule[-1].name='Allow-Traccar'
	uci set firewall.@rule[-1].src='wan'
	uci set firewall.@rule[-1].proto='tcp udp'
	uci set firewall.@rule[-1].dest_port='8082 5000-5150'
	uci set firewall.@rule[-1].target='ACCEPT'
	uci commit firewall
	fw4 reload >/dev/null 2>&1 || true
fi

echo
echo "Готово. Веб: http://<router>:8082  |  HTTPS: https://<domain>:8445"
echo "Приёмники GPS подключайте на порты 5000-5150 (в зависимости от протокола)."

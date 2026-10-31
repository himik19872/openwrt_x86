#!/bin/sh
# Установка панели уведомлений Telegram и мониторинга устройств сети
set -e
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== [1/4] Пакеты =="
apk add --no-cache jq curl arp-scan >/dev/null 2>&1 || true

echo "== [2/4] Файлы =="
mkdir -p /www/notify /etc/netmon
cp -f "$DIR/files/usr/libexec/netmon-api" /usr/libexec/netmon-api
cp -f "$DIR/files/usr/libexec/netmon-check" /usr/libexec/netmon-check
cp -f "$DIR/files/usr/libexec/netmon-scan" /usr/libexec/netmon-scan
cp -f "$DIR/files/usr/libexec/netmon-nets" /usr/libexec/netmon-nets
cp -f "$DIR/files/usr/libexec/notify-tg" /usr/libexec/notify-tg
cp -f "$DIR/files/www/notify/index.html" /www/notify/index.html
chmod +x /usr/libexec/netmon-api /usr/libexec/netmon-check /usr/libexec/netmon-scan /usr/libexec/netmon-nets /usr/libexec/notify-tg
ln -sf /usr/libexec/netmon-api /www/cgi-bin/netmon

echo "== [3/4] Данные =="
[ -f /etc/netmon/settings.json ] || printf '{"tg_token":"","tg_chat":"","devices":[],"settings":{"offline_confirm":2}}\n' > /etc/netmon/settings.json
[ -f /etc/netmon/known.json ] || printf '{}\n' > /etc/netmon/known.json
if getent group nutmon >/dev/null 2>&1; then
	chgrp nutmon /etc/netmon/settings.json 2>/dev/null || true
	chmod 640 /etc/netmon/settings.json 2>/dev/null || true
fi

echo "== [4/4] Cron =="
CRON=/etc/crontabs/root
grep -q netmon-check "$CRON" 2>/dev/null || echo "* * * * * /usr/libexec/netmon-check >/dev/null 2>&1" >> "$CRON"
grep -q netmon-scan "$CRON" 2>/dev/null || echo "*/5 * * * * /usr/libexec/netmon-scan --notify >/dev/null 2>&1" >> "$CRON"
/etc/init.d/cron restart >/dev/null 2>&1 || true

echo
echo "Готово. Панель: http://<router>/cgi-bin/netmon?action=ui"
echo "Впишите токен бота и chat_id в панели — там же список устройств и порог offline-подтверждений."

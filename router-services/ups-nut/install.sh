#!/bin/sh
# Установка мониторинга ИБП (NUT + веб-панель + Telegram-уведомления)
set -e
DIR=$(cd "$(dirname "$0")" && pwd)

echo "== [1/5] Пакеты =="
apk add --no-cache nut nut-server nut-upsmon nut-upsc jq curl >/dev/null 2>&1 || true

echo "== [2/5] Файлы =="
mkdir -p /www/ups
cp -f "$DIR/files/usr/libexec/upsadmin-api" /usr/libexec/upsadmin-api
cp -f "$DIR/files/usr/libexec/nut-telegram" /usr/libexec/nut-telegram
cp -f "$DIR/files/www/ups/index.html" /www/ups/index.html
chmod +x /usr/libexec/upsadmin-api /usr/libexec/nut-telegram
ln -sf /usr/libexec/upsadmin-api /www/cgi-bin/upsadmin

echo "== [3/5] Конфиги NUT =="
if [ -f /etc/config/nut_server ]; then
	echo "  /etc/config/nut_server уже существует — оставляю как есть"
else
	cp -f "$DIR/files/etc/config/nut_server" /etc/config/nut_server
	echo "  создан /etc/config/nut_server (не забудьте сменить пароль monuser!)"
fi
if [ -f /etc/config/nut_monitor ]; then
	echo "  /etc/config/nut_monitor уже существует — оставляю как есть"
else
	cp -f "$DIR/files/etc/config/nut_monitor" /etc/config/nut_monitor
fi

echo "== [4/5] API-ключ и права =="
[ -s /etc/upsadmin/api.key ] || hexdump -n 16 -e '16/1 "%02x"' /dev/urandom > /etc/upsadmin/api.key
mkdir -p /etc/upsadmin
chmod 600 /etc/upsadmin/api.key 2>/dev/null || true
# настройки Telegram для nut-telegram
[ -d /etc/netmon ] || mkdir -p /etc/netmon
[ -f /etc/netmon/settings.json ] || printf '{"tg_token":"","tg_chat":""}\n' > /etc/netmon/settings.json
chgrp nutmon /etc/netmon/settings.json 2>/dev/null || true
chmod 640 /etc/netmon/settings.json 2>/dev/null || true

echo "== [5/5] Запуск =="
/etc/init.d/nut-server enable 2>/dev/null || true
/etc/init.d/nut-monitor enable 2>/dev/null || true
/etc/init.d/nut-server restart >/dev/null 2>&1 || true
/etc/init.d/nut-monitor restart >/dev/null 2>&1 || true

echo
echo "Готово. Панель: http://<router>/cgi-bin/upsadmin?action=ui"
echo "Telegram: заполните /etc/netmon/settings.json (tg_token, tg_chat) или через панель «Уведомления»."
echo "Проверка: upsc ups@localhost"

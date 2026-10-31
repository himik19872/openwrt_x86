# Общие компоненты

nginx (HTTPS-прокси и роутинг поддоменов), карточки сервисов в LuCI и **важный фикс hairpin NAT**.

## Установка

```sh
sh common/install.sh
```

> Запускайте **после** `dns-domains` — установщик подставляет домен из `/etc/duckdns/sites.json` в nginx-конфиги.

## Что делает

1. **nginx** — копирует `nginx.conf` (сохраняя бэкап), подставляет домен, перезагружает.
   Слушает `8443` (Home Assistant) и `8445` (Traccar, из модуля traccar); поддомены на `443` генерирует `dns-domains`.
2. **Фикс hairpin NAT** — добавляет в `/etc/sysctl.conf`:
   ```
   net.bridge.bridge-nf-call-iptables=0
   net.bridge.bridge-nf-call-ip6tables=0
   ```
   Без этого пробросы портов не работают из локальной сети (подробно — в `docs/TROUBLESHOOTING.md`, раздел 1).
3. **LuCI** — пункт «Сервисы» с карточками: Home Assistant, Traccar, NVR, камера, UPS, уведомления, домены, LuCI.

## Файлы

```
files/etc/nginx/nginx.conf                       → /etc/nginx/nginx.conf
files/etc/nginx/conf.d/traccar.conf              → /etc/nginx/conf.d/traccar.conf (для модуля traccar)
files/etc/sysctl.conf                            → образец (в install.sh добавляется только нужное)
files/luci/menu.d/luci-app-webservices.json      → /usr/share/luci/menu.d/
files/luci/menu.d/luci-app-traccar.json          → /usr/share/luci/menu.d/
files/luci/view/webservices.js                   → /www/luci-static/resources/view/
files/luci/view/traccar.js                       → /www/luci-static/resources/view/
```

## Проверка

```sh
sysctl net.bridge.bridge-nf-call-iptables      # 0
nginx -t && /etc/init.d/nginx reload
# с LAN-клиента:
curl -I http://<wan-ip>:<проброшенный-порт>/
```

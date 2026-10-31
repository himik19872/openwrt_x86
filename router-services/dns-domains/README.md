# Домены и доступ — DuckDNS + nginx + dnsmasq

Управление поддоменами с веб-страницы на роутере. Один wildcard-сертификат, одинаковые адреса дома и снаружи.

## Как работает

```
Интернет ──▶ <wan-ip>:443 ──▶ nginx (server_name)
                              ├▶ <domain>            → роутер (LuCI, 127.0.0.1:80)
                              ├▶ nvr.<domain>        → 192.168.1.51:443  (NVR)
                              ├▶ video.<domain>      → 192.168.1.61:80   (камера)
                              └▶ ho.<domain>         → 192.168.1.30:8123 (Home Assistant)
LAN ──▶ dnsmasq: *.domain → 192.168.1.1 ──▶ тот же nginx
```

**Корень домена** удобно направлять на сам роутер (LuCI или портал сервисов), а устройства выносить в поддомены.

- DuckDNS отдаёт **wildcard** — регистрировать каждый поддомен не нужно;
- TLS — wildcard `*.<domain>` Let's Encrypt (DNS-01, acme.sh), автопродление по cron;
- поддомены и их назначения хранятся в `/etc/duckdns/sites.json`;
- `duckdns-apply` генерирует `/etc/nginx/conf.d/duckdns.conf` и `/etc/dnsmasq.d/duckdns.conf`;
- флаг **«Извне»** превращается в `allow 192.168.1.0/24; allow 10.66.66.0/24; deny all;` — сервис доступен только из LAN/VPN.

## Установка

```sh
sh install.sh
```

Ставит `jq curl openssl acme-acmesh`, копирует скрипты, включает `confdir /etc/dnsmasq.d`,
разрешает входящий TCP 443 в firewall и добавляет cron-задачу обновления IP.

### Сертификат (один раз)

```sh
/usr/lib/acme/client/acme.sh --issue --server letsencrypt --dns dns_duckdns \
    -d your.duckdns.org -d '*.your.duckdns.org' --home /etc/acme

/usr/lib/acme/client/acme.sh --install-cert -d your.duckdns.org --ecc \
    --key-file /etc/nginx/ssl/ha.key --fullchain-file /etc/nginx/ssl/ha.crt \
    --reloadcmd '/etc/init.d/nginx reload' --home /etc/acme
```

Токен DuckDNS берётся из `/etc/acme/account.conf` (`DuckDNS_Token`) или `/etc/duckdns/token`.

> ⚠️ DNAT-правило для порта 443 нужно удалить — порт 443 обслуживает nginx:
> `uci show firewall | grep redirect` → `uci delete firewall.@redirect[N]` → `uci commit firewall && fw4 reload`.

## Панель

`http://<router>/cgi-bin/dnsui` (только после входа root; в LuCI — «Сервисы → Домены и доступ»).

Что можно делать:
- добавлять/удалять поддомены, менять назначение (`http://ip:port` или с путём `/cgi-bin/x`);
- включать/выключать публикацию наружу;
- включать WebSocket (для Home Assistant и подобных);
- включить «локальный домен сети» — DHCP-домен станет `<domain>`, устройства получат имена `host.<domain>`;
- обновить IP в DuckDNS, перевыпустить сертификат, посмотреть лог.

## Файлы

```
files/usr/libexec/duckdns-apply → генератор nginx+dnsmasq конфигов
files/usr/libexec/duckdns-sync  → обновление A-записи DuckDNS (cron 5 мин)
files/usr/libexec/duckdns-api   → CGI-API панели
files/usr/libexec/duckdns-ui    → HTML панели за Basic Auth
files/www/dns/index.html        → интерфейс
files/etc/duckdns/sites.json    → список поддоменов (пример)
```

## Формат sites.json

```json
{
  "base": "example.duckdns.org",
  "listen_ip": "192.168.1.1",
  "local_domain": false,
  "sites": [
    { "sub": "",      "name": "Роутер (LuCI)", "target": "http://127.0.0.1",          "public": true,  "enabled": true, "ws": true },
    { "sub": "nvr",   "name": "NVR",           "target": "https://192.168.1.51:443", "public": true,  "enabled": true, "ws": true },
    { "sub": "video", "name": "Камера",        "target": "http://192.168.1.61:80",   "public": true,  "enabled": true, "ws": false },
    { "sub": "ups",   "name": "UPS",           "target": "http://127.0.0.1/cgi-bin/upsadmin", "public": false, "enabled": true }
  ]
}
```

`sub: ""` — корневой домен. `verify: true` — проверять сертификат бэкенда (по умолчанию отключено для самоподписанных).

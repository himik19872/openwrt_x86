# 🛠️ Сервисы роутера OpenWrt x86

Набор самодостаточных модулей для домашнего роутера на **OpenWrt 24.10 / 25.x (x86_64, apk, fw4 nftables)**:
VPN с веб-панелью, мониторинг ИБП, уведомления в Telegram, GPS-трекинг и управление доменом с поддоменами.

Каждый модуль ставится отдельным `install.sh`, не требует пересборки прошивки и безопасен для повторного запуска.

---

## 📦 Состав

| Модуль | Что делает | Интерфейс |
|---|---|---|
| [`wireguard`](wireguard/) | WireGuard-сервер + панель: добавление/удаление клиентов, QR-коды, .conf, вкл/выкл | `http://<router>/wgadmin/` |
| [`ups-nut`](ups-nut/) | NUT (usbhid-ups) + красивая панель: заряд, время работы, события, тест батареи, бипер | `http://<router>/cgi-bin/upsadmin?action=ui` |
| [`notify-netmon`](notify-netmon/) | Telegram-уведомления + мониторинг устройств сети (появление/пропажа, 2 подтверждения) | `http://<router>/cgi-bin/netmon?action=ui` |
| [`traccar`](traccar/) | Traccar в Docker: GPS-трекинг, HTTPS через nginx | `http://<router>:8082`, `https://<domain>:8445` |
| [`dns-domains`](dns-domains/) | Поддомены через DuckDNS wildcard + nginx (server_name роутинг) + dnsmasq split-horizon + wildcard TLS | `https://<sub>.<domain>/` |
| [`common`](common/) | nginx, LuCI-карточки «Сервисы», фикс hairpin NAT (br_netfilter от Docker) | LuCI → Сервисы |

---

## ⚡ Быстрая установка

> Требования: OpenWrt 24.10+ x86_64, доступ в интернет, ~50 МБ свободного места.

```sh
git clone https://github.com/himik19872/openwrt_x86.git /root/openwrt_x86
cd /root/openwrt_x86/router-services

sh wireguard/install.sh        # VPN + панель
sh ups-nut/install.sh          # ИБП (если есть USB-ИБП)
sh notify-netmon/install.sh    # Telegram + мониторинг сети
sh traccar/install.sh          # GPS-трекинг (нужен Docker)
sh dns-domains/install.sh      # домен и поддомены (nginx на 443)
sh common/install.sh           # nginx + LuCI-карточки + фикс hairpin
```

Порядок важен для `common` (он подставляет домен в nginx-конфиг из `/etc/duckdns/sites.json`, поэтому запускайте его **после** `dns-domains`).

---

## 🧩 Как это устроено

```
Интернет ──▶ роутер (fw4/nftables)
              │
              ├─ 443  nginx ──▶ по server_name: NVR / камера / HA / Traccar / UPS
              ├─ 8443 nginx ──▶ Home Assistant (HTTPS)
              ├─ 8445 nginx ──▶ Traccar
              ├─ 51820/udp    WireGuard
              └─ DNAT-пробросы (прямые порты устройств)

LAN ──▶ dnsmasq: *.domain → 192.168.1.1 (split-horizon, сертификат всегда валиден)
```

- **Все поддомены** в DuckDNS уже покрыты wildcard-записью — регистрировать каждый не нужно.
- **TLS** — один wildcard-сертификат Let's Encrypt (`DNS-01`), автопродление через acme.sh cron.
- **Панели** — статические HTML + CGI-API на `ash` + `jq`, авторизация по `root`/паролю роутера (Basic), плюс Bearer-ключ для автоматизации.

---

## 🔑 Секреты и доступы

| Файл | Назначение |
|---|---|
| `/etc/wgadmin/api.key` | Bearer-токен API WireGuard-панели |
| `/etc/upsadmin/api.key` | Bearer-токен API панели ИБП |
| `/etc/netmon/settings.json` | токен Telegram-бота и chat_id (права `root:nutmon 640`) |
| `/etc/duckdns/api.key` | Bearer-токен API панели доменов |
| `/etc/duckdns/token` | токен DuckDNS (если не хотите брать из `/etc/acme/account.conf`) |

Все `*.api.key` генерируются установщиками случайно и имеют права `600`. **В репозиторий они не попадают.**

---

## 🐞 Проблемы и решения

Смотрите [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — там разобраны:

- пробросы портов не работают из локальной сети (hairpin NAT) — **виноват `br_netfilter` от Docker**;
- `502 Bad Gateway` у CGI после установки;
- `403` LuCI при заходе по внешнему IP из LAN;
- DuckDNS и wildcard-поддомены;
- Docker не пускает трафик контейнеров в WAN.

---

## 📄 Лицензия

MIT — используйте и меняйте свободно.

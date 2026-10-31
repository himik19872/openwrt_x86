# WireGuard — сервер + панель управления

WireGuard-сервер на роутере и тёмная веб-панель для управления клиентами.

## Возможности

- добавление/удаление клиентов, выдача `.conf` и QR-кода (SVG);
- включение/выключение пира без удаления; список с handshake (онлайн/офлайн);
- скачивание готового конфига, ссылка для мобильных клиентов;
- Bearer-токен для скриптов (`/etc/wgadmin/api.key`).

## Установка

```sh
sh install.sh
```

Скрипт ставит `wireguard-tools qrencode jq`, копирует файлы, создаёт `wg0` (`10.66.66.1/24`, UDP 51820), зону firewall `wg` и правило на WAN.

## Файлы

```
files/usr/libexec/wgadmin-api      → /usr/libexec/wgadmin-api   (CGI-API)
files/www/wgadmin/index.html       → /www/wgadmin/index.html    (UI)
/etc/wgadmin/config.json           — endpoint, порт, DNS, allowed_ips, keepalive
/etc/wgadmin/clients.json          — список клиентов
/etc/wgadmin/server.key|server.pub — ключи сервера (создаются автоматически)
```

## API

| Запрос | Действие |
|---|---|
| `GET /cgi-bin/wgadmin?action=status` | сервер + список клиентов + handshake |
| `POST ...?action=add` `{"name":"phone"}` | создать клиента |
| `POST ...?action=toggle` `{"id":"..."}` | вкл/выкл |
| `POST ...?action=delete` `{"id":"..."}` | удалить |
| `GET ...?action=config&id=...` | отдать `.conf` |
| `GET ...?action=qr&id=...` | QR в SVG |

Авторизация: Basic (`root` + пароль роутера) либо `Authorization: Bearer $(cat /etc/wgadmin/api.key)`.

## Панель

`http://<router>/wgadmin/` — после установки появляется и в LuCI («Сервисы → WireGuard», если установлен `common`).

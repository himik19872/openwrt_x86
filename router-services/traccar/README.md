# Traccar — GPS-трекинг в Docker

Traccar в контейнере с публикацией портов и HTTPS-доступом через nginx роутера.

## Установка

```sh
apk add dockerd docker docker-compose        # если Docker ещё не установлен
sh install.sh
```

Скрипт создаёт контейнер `traccar` (`--restart unless-stopped`) с томами `traccar-logs` и `traccar-data`,
копирует `nginx/conf.d/traccar.conf`, добавляет правило firewall.

## Порты

| Порт | Назначение |
|---|---|
| `8082` | веб-интерфейс (HTTP) |
| `5000-5052` | приёмники GPS (tcp+udp) |
| `5055-5150` | приёмники GPS (tcp+udp) |
| `8445` | HTTPS через nginx (`https://<domain>:8445`) |

## Файлы

```
files/etc/nginx/conf.d/traccar.conf  → /etc/nginx/conf.d/traccar.conf
```

`server_name` подставляется установщиком из `/etc/duckdns/sites.json` (модуль `dns-domains`).
Сертификат — `/etc/nginx/ssl/ha.crt|ha.key` (wildcard Let's Encrypt).

## Docker + OpenWrt

Если контейнеры не имеют выхода в интернет или роутер блокирует трафик, см.
[`../docs/TROUBLESHOOTING.md`](../docs/TROUBLESHOOTING.md) — раздел 6.

Минимум:
```json
// /etc/docker-daemon.json
{"data-root":"/opt/docker","ip-forward-no-drop":true}
```
и зона `docker` с `forward ACCEPT` + forwarding `docker → wan`.

## LuCI

С модулем `common` появляется пункт «Сервисы → Traccar» (iframe + кнопка «открыть в новой вкладке»).

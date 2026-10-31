# Уведомления Telegram + мониторинг устройств сети

Панель с двумя функциями: отправка уведомлений в Telegram и контроль появления/пропажи устройств в локальной сети.

## Возможности

- токен бота и chat_id настраиваются в панели (не в конфиг-файле);
- список отслеживаемых устройств (имя, IP/MAC), алерты «устройство offline / online»;
- подтверждение offline двумя проверками подряд (без ложных срабатываний);
- сканирование сети `arp-scan` каждые 5 минут с поиском новых устройств;
- `/usr/libexec/notify-tg` — универсальный скрипт отправки (используется и NUT).

## Сканирование нескольких подсетей

`netmon-scan` и `netmon-api` сканируют **все IPv4-сети на `br-lan`** — список выдаёт `/usr/libexec/netmon-nets` (через `ipcalc.sh`).
Поэтому сервисные подсети (например `192.168.2.0/24` — заводская сеть камер OpenIPC) автоматически
попадают в мониторинг, и уведомления о новых устройствах приходят и оттуда.

Чтобы добавить такую подсеть роутеру:

```sh
uci add_list network.lan.ipaddr='192.168.2.1/24'
uci commit network
reboot          # ⚠️ не `network reload`!
```

Доступ из LAN к такой сети делает MASQUERADE:

```sh
uci add firewall nat
uci set firewall.@nat[-1].src='lan'
uci set firewall.@nat[-1].dest_ip='192.168.2.0/24'
uci set firewall.@nat[-1].target='MASQUERADE'
uci commit firewall && fw4 reload
```

> ⚠️ `network reload` после изменения `network.lan.ipaddr` на этом железе роняет сеть (br-lan пересоздаётся,
> Mellanox/igb не поднимаются) — применяйте перезагрузкой роутера.

## Надёжная доставка (важно)

При активном DPI соединения к `api.telegram.org` нестабильны: часть SYN/TLS-сессий просто не устанавливается
(симптом — сообщения «через раз», в логах `HTTP 000`). Скрипт `notify-tg` это компенсирует:

- **только IPv4** (`curl -4`) — локальный резолвер может отдавать IPv6, которого на роутере нет;
- **5 попыток** с паузой 1 с; 4xx (неверный токен/chat_id) не повторяются;
- последние попытки идут через принудительно рабочий IP (`--resolve api.telegram.org:443:149.154.167.220`),
  потому что DNS нередко отдаёт заблокированный адрес;
- параметры: `NOTIFY_TG_TRIES` (по умолчанию 5), `NOTIFY_TG_IP` (по умолчанию `149.154.167.220`);
- при полном провале — запись в syslog с тегом `notify-tg`.

В тестах: 15 из 15 сообщений доставлены (до правки — 3–5 из 10).

## Установка

```sh
sh install.sh
```

Ставит `jq curl arp-scan`, копирует скрипты, создаёт `/etc/netmon/{settings.json,known.json}` и cron-задачи.

## Файлы

```
files/usr/libexec/netmon-api   → /usr/libexec/netmon-api    (CGI-API + UI)
files/usr/libexec/netmon-check → /usr/libexec/netmon-check  (ping-проверка, cron 1 мин)
files/usr/libexec/netmon-scan  → /usr/libexec/netmon-scan   (arp-scan, cron 5 мин)
files/usr/libexec/netmon-nets  → /usr/libexec/netmon-nets   (список подсетей br-lan)
files/usr/libexec/notify-tg    → /usr/libexec/notify-tg     (отправка в Telegram)
files/www/notify/index.html    → /www/notify/index.html
/etc/netmon/settings.json      — токен, chat, устройства (root:nutmon 640)
/etc/netmon/known.json         — известные MAC для сканера
```

## Cron

```
* * * * *   /usr/libexec/netmon-check >/dev/null 2>&1
*/5 * * * * /usr/libexec/netmon-scan --notify >/dev/null 2>&1
```

## Панель

`http://<router>/cgi-bin/netmon?action=ui`

## API

| Запрос | Действие |
|---|---|
| `GET ?action=status` | настройки + список устройств + статусы |
| `POST ?action=save` | сохранить токен/chat/устройства |
| `POST ?action=test` | отправить тестовое сообщение |
| `POST ?action=scan` | запустить сканирование сейчас |

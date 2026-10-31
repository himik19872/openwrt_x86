# ИБП — NUT + веб-панель + Telegram

Мониторинг USB-ИБП: заряд, время автономной работы, напряжение, события питания.
Панель показывает состояние в реальном времени, позволяет запустить самотест батареи и переключить бипер.

## Возможности

- `upsc`-данные: `battery.charge`, `battery.runtime`, `battery.voltage`, статус;
- история событий питания (on-line / on-batt / low-batt / comm-bad);
- кнопки «самотест батареи», «бипер вкл/выкл»;
- уведомления в Telegram через NUT `NOTIFYCMD` (`nut-telegram`);
- корректное выключение роутера (`nutshutdown`) при разряде.

## Установка

```sh
sh install.sh
```

Ставит `nut nut-server nut-upsmon nut-upsc`, копирует скрипты и конфиги (существующие `/etc/config/nut_*` не перезаписывает).

> После установки **смените пароль** `monuser` в `/etc/config/nut_server` и `/etc/config/nut_monitor` (по умолчанию `CHANGE_ME_STRONG_PASSWORD`).

## Файлы

```
files/usr/libexec/upsadmin-api   → /usr/libexec/upsadmin-api    (CGI-API + UI)
files/usr/libexec/nut-telegram   → /usr/libexec/nut-telegram    (NOTIFYCMD)
files/www/ups/index.html         → /www/ups/index.html
files/etc/config/nut_server      → /etc/config/nut_server       (пример: usbhid-ups, listen 3493)
files/etc/config/nut_monitor     → /etc/config/nut_monitor      (upsmon master + notify)
```

## Настройка

1. `upsc -l` — проверьте, что ИБП виден (`driver: usbhid-ups`, например PPC 06da:ffff).
2. `upsc ups@localhost` — телеметрия.
3. Telegram: заполните `/etc/netmon/settings.json` → `{"tg_token":"...","tg_chat":"..."}` (права `root:nutmon 640`) или через панель «Уведомления».
4. `lowbatnotify` — именно так называется опция `LOWBATT` в UCI (не `lowbattnotify`).

## Панель

`http://<router>/cgi-bin/upsadmin?action=ui`

## API

| Запрос | Действие |
|---|---|
| `GET ?action=status` | все переменные `upsc` + статус подключения |
| `GET ?action=events` | журнал событий питания |
| `POST ?action=test.battery.start` | самотест батареи |
| `POST ?action=beeper.toggle` | переключить бипер |

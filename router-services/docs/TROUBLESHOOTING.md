# 🐞 Решение проблем

Собрано по реальному опыту эксплуатации OpenWrt 25.x x86_64 + Docker + fw4 (nftables).

---

## 1. Пробросы портов (DNAT) не работают из локальной сети, а из интернета работают

**Симптомы**
- `http://<wan-ip>:3001` из LAN — таймаут; снаружи (телефон по LTE / check-host.net) — 200.
- Сервисы самого роутера (LuCI 80, Traccar 8082, nginx 8443) из LAN работают.
- `tcpdump -ni br-lan` показывает **каждый пакет дважды**.

**Причина** — `br_netfilter`, который тянет Docker:

1. `dockerd` зависит от `kmod-ipt-physdev` → `kmod-br-netfilter`.
2. Пакет `dockerd` ставит `/etc/sysctl.d/12-br-netfilter-ip.conf`:
   ```
   net.bridge.bridge-nf-call-iptables=1
   net.bridge.bridge-nf-call-ip6tables=1
   ```
3. При включённом bridge-файрволе трафик LAN↔LAN проходит через netfilter дважды. fw4-reflection выполняет DNAT (`prerouting`), но `snat` в цепочке `srcnat_lan` **не применяется** — ответ уходит клиенту с адресом источника `192.168.1.51`, клиент его отбрасывает.

**Диагностика**
```sh
sysctl net.bridge.bridge-nf-call-iptables          # 1 = проблема
lsmod | grep br_netfilter
nft list chain inet fw4 srcnat_lan | head          # правила есть, но не работают
# проверка: отключить и повторить
sysctl -w net.bridge.bridge-nf-call-iptables=0
```

**Решение** (постоянное) — переопределить в `/etc/sysctl.conf`, он читается последним (`/etc/init.d/sysctl`, START=11, после загрузки модулей):
```
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
```
Или просто: `sh router-services/common/install.sh`.

Модуль `br_netfilter` остаётся загруженным (Docker доволен), bridge-файрвол выключен. После этого hairpin работает для **всех** DNAT-портов.

> Проверка после перезагрузки: `sysctl net.bridge.bridge-nf-call-iptables` → `0`.

---

## 2. `502 Bad Gateway` у CGI-панели

uhttpd отдаёт 502, если CGI-процесс завершился без вывода. Частые причины:

- **синтаксис/CRLF**: файл скопирован из Windows — прогоните `tr -d '\r' < file > tmp && mv tmp file`;
- **огромные аргументы jq**: конструкция `jq -n --argjson cfg "$(cat big.json)"` может падать; надёжнее
  `jq --arg x "$x" '{...}' file.json` (читать файл, а не передавать его строкой);
- **нет `jq`** в PATH uhttpd (обычно `PATH=/sbin:/usr/sbin:/bin:/usr/bin` — проверьте `apk add jq`);
- отладка: `exec 2>/tmp/cgi.err; set -x` в начале скрипта и повторить запрос.

---

## 3. nginx-прокси ломает путь (`/cgi-bin/upsadmincgi-bin/upsadmin`)

`proxy_pass` **с URI** заменяет совпавшую часть `location`:

```nginx
# плохо: /cgi-bin/upsadmin?action=status → /cgi-bin/upsadmincgi-bin/upsadmin?action=status
location / { proxy_pass http://127.0.0.1/cgi-bin/upsadmin; }

# хорошо: путь сохраняется, а префикс добавляется rewrite'ом
location / {
    rewrite ^ /cgi-bin/upsadmin$uri break;
    proxy_pass http://127.0.0.1;
}
```

Правило: если сервис должен жить «по пути», в `proxy_pass` указывайте только origin (`scheme://host:port`), а путь добавляйте через `rewrite`.

---

## 4. LuCI отдаёт 403 при заходе по внешнему IP из LAN

uhttpd по умолчанию фильтрует RFC1918-адреса:
```sh
uci set uhttpd.main.rfc1918_filter='0'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

---

## 5. DuckDNS: поддомены и wildcard

- DuckDNS отдаёт **wildcard** для любого `<что-угодно>.<name>.duckdns.org` — отдельные поддомены создавать не нужно.
- Бесплатный лимит 5 «доменов» касается только корневых имён, не поддоменов.
- A-запись обновляется через API (`/usr/libexec/duckdns-sync`, cron каждые 5 минут):
  `https://www.duckdns.org/update?domains=<name>&token=<token>&ip=`
- Токен: `/etc/acme/account.conf` (строка `DuckDNS_Token='...'`) или `/etc/duckdns/token`.

**Сертификат** — wildcard через DNS-01:
```sh
/usr/lib/acme/client/acme.sh --issue --server letsencrypt --dns dns_duckdns \
    -d example.duckdns.org -d '*.example.duckdns.org' --home /etc/acme
```
⚠️ По умолчанию acme.sh уходит на ZeroSSL и требует регистрации — всегда указывайте `--server letsencrypt`.

---

## 6. Docker не пускает контейнеры в интернет / блокирует трафик

Docker добавляет в `DOCKER-USER` правило `REJECT`, а fw4 создаёт зону `docker` с `forward REJECT`. Решение:

```sh
# 1) не сбрасывать форвардинг (иначе контейнеры без интернета)
uci set dockerd.globals.alt_config_file='/etc/docker-daemon.json'
# /etc/docker-daemon.json
# {"data-root":"/opt/docker","ip-forward-no-drop":true}
uci commit dockerd
/etc/init.d/dockerd restart

# 2) зона docker без block
uci set firewall.docker.forward='ACCEPT'
uci set firewall.docker.masq='1'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='docker'
uci set firewall.@forwarding[-1].dest='wan'
uci commit firewall
fw4 reload
```

---

## 7. `network reload` роняет сеть (br-lan, Mellanox/igb)

**Симптом:** после `uci commit network && /etc/init.d/network reload` (например, при добавлении второго адреса
в `network.lan.ipaddr`) связь пропадает полностью — помогает только физическая перезагрузка.

**Причина:** при изменении `ipaddr` netifd пересоздаёт интерфейс `br-lan`; на этом железе
(Mellanox ConnectX-2 + igb) порты после этого не поднимаются автоматически.

**Решение:**
- не использовать `network reload` после правки `ipaddr` — применять **перезагрузкой роутера**
  (`reboot`), при загрузке netifd поднимает br-lan с обоими адресами корректно;
- безопасные альтернативы на живой системе: `ip addr add 192.168.2.1/24 dev br-lan` (временно,
  без участия netifd) или собственный hotplug-скрипт;
- правила firewall применять отдельно: `fw4 reload` — сеть не рвёт.

Проверка после перезагрузки:
```sh
ip -4 addr show br-lan          # оба адреса на месте
nft list ruleset | grep masquerade
```

---

## 8. Мелочи, которые экономят часы

| Проблема | Решение |
|---|---|
| `jq` 1.8 без ONIGURUMA | нет `test/match/capture` — используйте `split/join/startswith` |
| `qrencode` без PNG | генерируйте SVG: `qrencode -t SVG -o -` |
| `scp` на старый dropbear | `scp -O` (legacy protocol) |
| `ash`: `jq ... \| while ... & done; wait` не ждёт | подавайте файл: `done < file` |
| `dropbear` игнорирует `~/.ssh/authorized_keys` | ключи в `/etc/dropbear/authorized_keys` |
| uhttpd не передаёт `HTTP_X_*` в CGI | доступны только `HTTP_AUTHORIZATION/COOKIE/HOST/USER_AGENT/ACCEPT` |
| fw4 `default_server 444` | `return 301 https://<domain>$request_uri` — понятнее для пользователя |
| `nmap`/`pkill`/`timeout` отсутствуют | `nmap` — `apk add nmap`; вместо `timeout` используйте `tcpdump -c N` + `kill` |

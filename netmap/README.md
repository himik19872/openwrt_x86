# Карта сети — мониторинг и топология

Инструменты для инвентаризации и визуализации сети в большом частном доме:
ядро Eltex, D-Link, пять PoE-коммутаторов, три роутера на OpenWrt, серверы и камеры.

## Состав

| Файл | Назначение |
|---|---|
| `collect2.sh` | сбор данных: ARP-скан + telnet/SSH-опрос всех управляемых коммутаторов → `/root/netmap/*.txt` |
| `report3.sh` | сводная таблица `IP → MAC → коммутатор → порт → имя порта` |
| `tree.sh` | дерево топологии: кто на каком порту, какие коммутаторы связаны между собой |
| `report-*.txt` | снимки состояния сети |

## Устройства

| IP | Устройство | Управление | SNMP | LLDP |
|---|---|---|---|---|
| .1 | роутер (OpenWrt x86, ядро сети) | SSH | — | — |
| .245 | **Eltex** (ядро) | telnet/SSH/Web `admin/admin` | только через Web | CLI `show lldp neighbors` |
| .108 | **D-Link DGS-1210-10/ME** | telnet/SSH/Web `admin` | через Web | ✅ включён |
| .54 | **sw10g** XikeStor SKS8300-8X (RTL9303, OpenWrt) | SSH/Web | ✅ `public` | ✅ |
| .120 | OpenWrt 25.12.6 (`OpenWrt2`) | SSH | ✅ `public` | ✅ |
| .244 | OpenWrt 23.05.5 (`OpenWrt3`) | SSH | ✅ `public` | ✅ |
| .46 .110 .133 | PoE Shenzhen SSC | только Web | — | — |
| .116 .126 | PoE (dc:32:62) | только Web | — | — |

## Как работает определение «кто за каким портом»

Все коммутаторы в одном VLAN (плоская сеть), поэтому **каждый учит все MAC-адреса**.
Полезная информация — не «где видно устройство», а **где оно входит в сеть**:

1. Собираем таблицу MAC (FDB) с каждого коммутатора.
2. Строим таблицу MAC по портам.
3. Если на порту много MAC и среди них MAC другого коммутатора — это **uplink**.
4. Устройство считается подключённым к тому коммутатору, где оно видно на порту
   с наименьшим числом MAC (то есть ближе к краю).

## Запуск

```sh
# на роутере 192.168.1.1
/root/netmap/collect2.sh     # ~3 минуты
/root/netmap/report3.sh      # сводная таблица
/root/netmap/tree.sh         # дерево
```

Результаты: `/root/netmap/report.txt`, `/root/netmap/fdb-all.txt`,
`/root/netmap/arp.txt`, `/root/netmap/eltex-mac.txt` и т.д.

## Требования к окружению

- На роутере: `arp-scan`, `nc`, `ssh`, ключ `/root/.ssh/id_ed25519` (dropbearkey).
- Ключ роутера добавлен в `/etc/dropbear/authorized_keys` на всех OpenWrt-устройствах.
- На OpenWrt-коммутаторах установлены `snmpd` и `lldpd`, community `public` (только чтение).
- На D-Link включён LLDP: `enable lldp` + `save`.
- Eltex опрашивается через telnet (`nc host 23`), пароль передаётся посимвольно с паузами.

## Грабли

| Проблема | Решение |
|---|---|
| `bridge fdb show` на OpenWrt — `bridge: not found` | использовать `brctl showmacs <мост>` (пакет `bridge` не установлен, но `brctl` есть) |
| dropbear-SSH не понимает `UserKnownHostsFile=` и `ConnectTimeout=` | передавать только `-o StrictHostKeyChecking=no` |
| `comm`, `od`, `cat -A`, `base64` отсутствуют в busybox | `apk add coreutils-base64`, либо обходиться `awk`/`sed` |
| `ip -4 route` и `ip -br` не работают | busybox `ip` без этих ключей |
| Eltex: `snmp-server community` не принимается в CLI | community задаётся только через веб-интерфейс |
| Eltex CLI: `configure` → `% Incomplete command` | нужен полный `configure terminal` |
| Вывод Eltex/D-Link разбит на страницы | после команды слать пробелы с паузой ~1 с, затем `\r\n` |
| Файлы, залитые с Windows, ломают shebang | `sed -i 's/\r$//' file` |

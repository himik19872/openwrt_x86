# Прошивка 10G-коммутатора XikeStor SKS8300-8X в OpenWrt

Практическое руководство, проверенное на живом устройстве (04.11.2026).
Заменяет заводскую прошивку `V300SP10240913` на **OpenWrt 25.12.0** (target `realtek/rtl930x`).

---

## Железо (проверено)

| Параметр | Значение |
|---|---|
| Модель | **XikeStor SKS8300-8X** |
| То же самое | ONTi ONT-S508CL-8S / JT-COM JT-FG6700-8TFM / Hicomdata HK-ES3058-8P-L |
| SoC | **Realtek RTL9303 rev B** (`RTL9303_8XGE` в U-Boot) |
| Порты | 8× SFP+ (1G/10G), DSA-интерфейсы `lan1…lan8` |
| RAM / flash | 512 МБ / 32 МБ NOR (30 МБ «firmware» + 1 МБ u-boot + board-info + syslog) |
| Консоль | порт Console, **9600 8N1** |
| Заводская прошивка | `V300SP10240913`, BootRom V2.00, web + telnet/SSH CLI |
| Управление после прошивки | LuCI (`http://<ip>/`), SSH root |

---

## Требования

1. **Консольный кабель** USB↔RJ45 (Cisco-совместимый). Подойдёт любой на FT232/CH340/PL2303.
   Лучше подключать к хосту с Linux/OpenWrt — там проще автоматизировать вход в U-Boot.
2. Хост с **TFTP** (и/или HTTP) в той же L2, что и коммутатор.
3. SFP+ модуль/DAC в **порту 1** — U-Boot умеет поднимать только Port 1.
4. Образы OpenWrt:
   ```
   https://downloads.openwrt.org/releases/25.12.0/targets/realtek/rtl930x/
   openwrt-25.12.0-realtek-rtl930x-xikestor_sks8300-8x-initramfs-kernel.bin
   openwrt-25.12.0-realtek-rtl930x-xikestor_sks8300-8x-squashfs-sysupgrade.bin
   ```
   Обязательно сверьте `sha256sums` с официальным файлом.

---

## Шаг 0. Бэкап заводской прошивки (обязательно!)

В заводском веб-интерфейсе (`http://192.168.1.54/`, `admin/admin`):
**Firmware Upgrade → TFTP** → `Server IP` = ваш TFTP-сервер, `Server File Name` = `nos.img`,
`Operation Type` = **Upload**, `Type` = binary → Apply.

Поднять TFTP-сервер на OpenWrt-роутере:

```sh
apk add atftpd
mkdir -p /tmp/tftp && chmod 777 /tmp/tftp
touch /tmp/tftp/nos.img && chmod 666 /tmp/tftp/nos.img   # файл-приёмник нужен заранее
atftpd --daemon --port 69 --logfile /tmp/atftpd.log --user root --group root /tmp/tftp
# затем забрать файл: scp root@router:/tmp/tftp/nos.img .
```

Альтернатива — сохранить `startup.cfg` тем же способом (`Local File Name` = `startup.cfg`):
это текстовый конфиг, пригодится для переноса настроек.

> Дамп `nos.img` **зашифрован вендором** (высокая энтропия, нет сигнатур), но для отката подходит как есть.

---

## Шаг 1. Подключить консоль

```sh
# на OpenWrt-хосте
apk add kmod-usb-serial kmod-usb-serial-ftdi kmod-usb-serial-pl2303 kmod-usb-serial-ch341 \
        coreutils-stty socat picocom
# кабель появится как /dev/ttyUSB0
stty -F /dev/ttyUSB0 9600 cs8 -cstopb -parenb -crtscts clocal cread raw -echo -ixon -ixoff -hupcl
```

Проверка связи:

```sh
( cat /dev/ttyUSB0 & CP=$!; sleep 1; printf '\r' > /dev/ttyUSB0; sleep 2; kill $CP ) | tail -5
```

---

## Шаг 2. Перехватить U-Boot (Boot Menu)

При включении питания нужно успеть послать **Ctrl+B** (`0x02`) — удобно спамить его в течение
первых секунд загрузки. Скрипт [`scripts/con-spam.sh`](scripts/con-spam.sh) делает это 6 минут:

```sh
setsid ./scripts/con-spam.sh 1800 </dev/null >/dev/null 2>&1 &
```

Выключите и включите питание коммутатора. Должно появиться:

```
######## Uboot for Flash Main Menu ########
 [1] Enable Network On
 [2] Config Ethernet Environment Variables
 [3] Ping Host IP Address
 [4] Running the System Kernel image
 [5] Burn the production firmware Bin
 ...
Enter your selection:
```

Остановите спам, иначе меню будет перерисовываться:

```sh
for p in $(ps w | awk '/con-spam/{print $1}'); do kill $p; done
```

Дальше удобнее работать через `picocom` (`picocom -b 9600 /dev/ttyUSB0`) **или** скриптом
[`scripts/ub-cmd.sh`](scripts/ub-cmd.sh) — он отправляет команду посимвольно с задержкой.
⚠️ **Важно:** при быстрой отправке строки через `/dev/ttyUSB0` часть символов теряется —
именно поэтому нужен посимвольный скрипт.

---

## Шаг 3. Вход в U-Boot

В меню нажмите **Ctrl+F** (`0x06`) → `Enter the password:(1-32 characters)` → введите:

```
diagshell_unipoe_env
```

Должен появиться промпт `Boot#`. Затем:

```
debug_unish_env
```

→ промпт `RTL9300#` (это Realtek-шелл внутри U-Boot).

Проверить окружение (полезно):

```
printenv
```
```
boardmodel=RTL9303_8XGE
ipaddr=192.168.2.1        <-- по умолчанию совпадает с часто используемым шлюзом!
serverip=192.168.2.36
ethact=rtl9300#0
```

---

## Шаг 4. Поднять сеть и загрузить initramfs

Порт 1 (в него должен быть вставлен SFP+/DAC, ведущий к TFTP-серверу):

```
rtk 10g 0 fiber10g          # или  fiber1g, если модуль 1G
rtk ext-devInit 0
rtk ext-pinSet 2 0
```

Адреса (подставьте свои; сервер не должен совпадать с `ipaddr`):

```
setenv ipaddr 192.168.2.37
setenv serverip 192.168.2.1
ping 192.168.2.1
```

Ожидаемо: `host 192.168.2.1 is alive`. Затем загрузка образа в RAM:

```
tftpboot 0x82000000 openwrt-25.12.0-realtek-rtl930x-xikestor_sks8300-8x-initramfs-kernel.bin
bootm
```

Через ~10–15 секунд появится `root@(none):~#` — это OpenWrt в оперативной памяти (флеш ещё не тронут).

---

## Шаг 5. Записать OpenWrt на флеш

В initramfs сетевой интерфейс называется **`switch.1`** (не `br-lan`!):

```sh
ip addr add 192.168.2.37/24 dev switch.1
ping -c 2 192.168.2.1
```

Скачать sysupgrade-образ. **`tftp`-клиента в initramfs нет**, используйте HTTP
(на сервере положить файл в `/www/`, у нас — uhttpd на роутере):

```sh
cd /tmp
wget -O fw.bin http://192.168.2.1/fw.bin
ls -l /tmp/fw.bin
```

Проверить разделы и стереть старую прошивку:

```sh
cat /proc/mtd
# mtd3 = "firmware" (30 МБ)
mtd erase firmware
```

Прошить (питание не выключать!):

```sh
sysupgrade -n /tmp/fw.bin
```

Устройство само перезагрузится. **Первый старт занимает ~40–60 секунд.**

---

## Шаг 6. После прошивки

По умолчанию коммутатор поднимается на **192.168.1.1/24** — если такой адрес уже занят вашим
роутером, будет конфликт. Сразу поменяйте адрес по консоли:

```sh
uci set network.lan.ipaddr='192.168.1.54/24'
uci commit network
/etc/init.d/network reload
passwd root          # обязательно задать пароль (по умолчанию он пустой)
```

Проверка:

```sh
ping 192.168.1.54
http://192.168.1.54/      # LuCI
ssh root@192.168.1.54
```

Порты — обычные Ethernet-интерфейсы (`lan1…lan8`), настраиваются в LuCI → Network → Interfaces,
никакого «Cisco CLI» больше нет. VLAN'ы — через `bridge-vlan` в `/etc/config/network`.

---

## Шаг 7. Базовая настройка: сеть, время, русский язык

### 7.1 Сеть, имя, часовой пояс

Штатный образ отдаёт только `lan` со статическим адресом — **шлюза и DNS нет**, поэтому нет
ни обновлений пакетов, ни синхронизации времени:

```sh
uci set network.lan.gateway='192.168.1.1'
uci -q delete network.lan.dns
uci add_list network.lan.dns='192.168.1.1'
uci add_list network.lan.dns='8.8.8.8'

uci set system.@system[0].hostname='sw10g'
uci set system.@system[0].description='XikeStor SKS8300-8X'
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'

uci commit network; uci commit system
reload_config      # применяет всё, сеть моргнёт на 2–3 секунды
```

Проверка:

```sh
ip route                    # default via 192.168.1.1 dev switch.1
ping -c2 1.1.1.1
cat /proc/sys/kernel/hostname
```

> ⚠️ В штатном образе busybox `ip` **не понимает `-4`/`-br`** — `ip -4 route` выдаст
> «usage», а не ошибку маршрута. Используйте `ip route` / `ip addr show`.

### 7.2 Время — до установки пакетов!

После прошивки часы стоят на дате сборки (`Mar 3 2026`), из-за чего `apk update` падает
с `wgetSSL verify error: unknown error` (сертификаты «из будущего»). Лечится так:

```sh
date -u -s '2026-11-04 11:18:56'      # один раз выставить вручную
/etc/init.d/sysntpd enable
/etc/init.d/sysntpd restart           # дальше время держит busybox ntpd
date
```

### 7.3 Русский язык LuCI

```sh
apk update
apk add luci-i18n-base-ru luci-i18n-firewall-ru \
        luci-i18n-package-manager-ru luci-i18n-attendedsysupgrade-ru \
        zoneinfo-core zoneinfo-europe
uci set luci.main.lang='ru'
uci commit luci
```

`zoneinfo-core` + `zoneinfo-europe` нужны, чтобы в LuCI → Система корректно отображался
и выбирался часовой пояс (без них список зон пустой). Перезагрузка не требуется —
интерфейс сразу на русском (меню «Статус / Система / Сеть», «Интерфейсы», «Межсетевой экран»).
Занято на оверлее после установки: **~1 МБ из 19.4 МБ**.

### 7.4 Имя в DNS роутера

Чтобы коммутатор пинговался как `sw10g.lan`, на роутере (192.168.1.1):

```sh
uci set dhcp.sw10g='domain'
uci set dhcp.sw10g.name='sw10g'
uci set dhcp.sw10g.ip='192.168.1.54'
uci add_list dhcp.sw10g.name='sw10g.lan'
uci commit dhcp
/etc/init.d/dnsmasq reload
```

### 7.5 Бэкап конфигурации

```sh
sysupgrade -b /tmp/backup-sw10g.tar.gz     # 8 КБ, 31 файл
```

Забрать на ПК:

```sh
# в образе нет sftp-server, поэтому pscp/scp не работают — забираем через base64
apk add coreutils-base64
base64 /tmp/backup-sw10g.tar.gz > /tmp/b64.txt      # затем скачать и раскодировать локально
```

Восстановить: `sysupgrade -r backup-sw10g.tar.gz`.

### 7.6 Сколько ждать после перезагрузки (важно!)

**Не считайте коммутатор «умершим» раньше, чем через 2 минуты.** Замерено на этом железе:

| Этап | Время |
|---|---|
| U-Boot | ~20 с |
| ядро до старта DSA-драйвера | ~38 с |
| инициализация SerDes **каждого** из 8 портов (10gbase-r) | ~5.5 с × 8 ≈ 45 с |
| появление IP/SSH/LuCI | **~65 с от старта ядра** |
| **от команды `reboot` до ответа на ping** | **~95–100 с** |

Симметрично: первые ~40 секунд в логе тишина, затем идут блоки
`start_1.1.1 … end_1.4.2` — это калибровка канала 10G для порта lan1, lan2 и т.д.
Пока все порты не откалиброваны, у моста `switch` нет линка, и адрес `192.168.1.54`
не отвечает (`ping` в это время может отдавать «port unreachable» или молчать).

Проверить, что загрузка идёт, а не зависла:

```sh
cat /proc/uptime                                  # счётчик растёт -> живой
dmesg | tail -5                                   # видны блоки start_/end_ калибровки
for p in lan1 lan2 lan3 lan4 lan5 lan6 lan7 lan8; do
  printf "%s=%s " $p $(cat /sys/class/net/$p/operstate); done
```

Ускорить нельзя: калибруются все порты бриджа, в том числе пустые SFP+.
Если порт не нужен — можно не включать его в `bridge-vlan`, тогда он не поднимается
и калибровка для него не выполняется (минус ~5 с на порт).

### 7.7 Вставили SFP-модуль после включения — линка нет

Симптом: порт в `lowerlayerdown`, `carrier=0`, `Link detected: no`, хотя модуль виден
по I2C (`ethtool -m lanN` отдаёт EEPROM) и кабель воткнут.

Причина: режим порта выбирается **при загрузке**, по наличию и типу модуля
(phylink + SFP-описание). Модуль, вставленный в работающий коммутатор, сам порт
не переинициализирует.

Лечение без перезагрузки (достаточно 1–2 секунд down):

```sh
for p in lan4 lan5; do ip link set $p down; sleep 1; ip link set $p up; done
sleep 8
for p in lan4 lan5; do echo "$p $(cat /sys/class/net/$p/operstate) $(cat /sys/class/net/$p/speed)"; done
```

В логе должно появиться:

```
lan5: PHY [smbus:sfp-p5:16] driver [Marvell 88E1111] (irq=POLL)
lan5: Link is Up - 1Gbps/Full - flow control rx/tx
```

Если модули уже стоят — после `reboot` порты поднимаются сами, ничего делать не нужно.

| Модуль | Режим порта | Скорость |
|---|---|---|
| 10G SFP+ (оптика/DAC/CR) | `inband/10gbase-r` | 10 Гбит/с |
| медь 1000BASE-T (напр. ORIGO OFM712, внутри Marvell 88E1111) | `inband/sgmii` | 1 Гбит/с |

Проверить, что за модуль стоит в порту:

```sh
ethtool -m lan4 | head -8      # EEPROM: вендор, P/N, скорость (12-й байт = 0x0d -> 1.3 ГБод = 1G)
ethtool lan4 | grep -E "Supported link modes|Link detected"
```

---

## Грабли, на которые мы наступили

| Проблема | Решение |
|---|---|
| Строки в U-Boot вводятся с потерями символов | отправлять **посимвольно** с задержкой (`scripts/ub-cmd.sh`) |
| `cat /dev/ttyUSB0` даёт «кашу» | использовать `picocom` или `stty raw` + `socat`; на 115200/57600 — тишина, скорость именно **9600** |
| `ipaddr=192.168.2.1` в U-Boot по умолчанию | задать другой адрес (`setenv ipaddr 192.168.2.37`) |
| в initramfs нет `br-lan` | интерфейс называется `switch.1` |
| в initramfs нет `tftp` | качать образ по HTTP (`wget`) |
| после прошивки адрес `192.168.1.1` конфликтует с роутером | сменить на свободный через консоль |
| `root` без пароля | `passwd root` сразу после прошивки |

---

## Восстановление (если что-то пошло не так)

1. U-Boot не затрагивается — он в отдельном разделе `u-boot` (1 МБ) и остаётся доступным по консоли.
2. Заходим в Boot Menu (`Ctrl+B`), `Ctrl+F`, пароль `diagshell_unipoe_env`.
3. Восстановление заводской прошивки: пункт **[5] Burn the production firmware Bin** (по TFTP),
   указав ранее сохранённый `nos.img`.
4. Либо повторяем `tftpboot …initramfs` → `bootm` и прошиваем sysupgrade заново.

---

## Скрипты

| Файл | Назначение |
|---|---|
| [`scripts/ub-cmd.sh`](scripts/ub-cmd.sh) | отправить команду в консоль посимвольно + прочитать ответ |
| [`scripts/ub-login.sh`](scripts/ub-login.sh) | автоматический вход: `Ctrl+F` + пароль `diagshell_unipoe_env` |
| [`scripts/con-spam.sh`](scripts/con-spam.sh) | спам `Ctrl+B` при загрузке (перехват Boot Menu) |
| [`scripts/con-log.sh`](scripts/con-log.sh) | непрерывный лог консоли в `/tmp/con.log` |

Пример работы:

```sh
./scripts/ub-cmd.sh "rtk 10g 0 fiber10g" 3
tr -d '\000' < /tmp/ubc.out | sed 's/\r//g' | tail -5
```

---

## Лицензия

MIT. Все действия выполняются на ваш риск: прошивка через U-Boot подразумевает возможность
«кирпича» при обрыве питания — восстанавливать всё равно через консоль + сохранённый `nos.img`.

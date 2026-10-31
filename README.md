# 🖥️ OpenWrt x86 — Asterisk SIP Monitor + go2rtc

[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10.5-00b894)](https://openwrt.org)
[![Asterisk](https://img.shields.io/badge/Asterisk-20.8.1-FF8800)](https://asterisk.org)
[![Flask](https://img.shields.io/badge/Flask-3.1-000000)](https://flask.palletsprojects.com)

Полная инфраструктура для IP-домофонии и видеонаблюдения на базе **OpenWrt x86**. 
Включает Asterisk PBX с веб-интерфейсом, запись звонков, go2rtc для видеокамер, 
и интеграцию с LuCI (OpenWrt Web UI).

---

## 📋 Состав проекта

| Компонент | Назначение | Порт |
|-----------|-----------|------|
| **Asterisk 20** | SIP-ATC для IP-домофонов (Beward, Dahua, OpenIPC) | UDP 5060 |
| **Flask-монитор** | Веб-интерфейс управления SIP-пирами, записями звонков | TCP 5000 |
| **go2rtc** | Трансляция RTSP-камер в WebRTC/HLS | TCP 1984 |
| **LuCI** | Пункты меню в OpenWrt Web UI | TCP 80/443 |
| **CDR** | Логирование звонков в CSV | — |
| **MixMonitor** | Запись аудио звонков (WAV) | — |

---

## ✨ Возможности Asterisk Monitor

- 📋 **Список SIP-пиров** — онлайн/офлайн статус, задержка, тип устройства
- ✏️ **Редактирование пиров** — создание, удаление, изменение пароля/типа
- 🎙 **Записи звонков** — прослушивание, скачивание, удаление
- 🔄 **Автоочистка** — записей старше 7 дней (cron каждое воскресенье)
- 🚪 **Быстрые действия** — открыть подъезд, перезагрузить конфиг
- 🏠 **Ссылка на OpenWrt** — быстрый возврат в LuCI

### Типы устройств
- 🚪 **Beward / Dahua / Rubitek / OpenIPC** — вызывные панели (контекст `call-panels`)
- 🏠 **Квартира** — внутренние SIP-аппараты (контекст `apartments`, с голосовой почтой)
- 📱 **Другое** — SIP-софтфоны, SIP-транки

---

## ⚡ Быстрая установка

> **Требования:** OpenWrt 24.10 x86_64, интернет, ~20 MB свободного места.

```bash
# 1. Скачать репозиторий
cd /root
wget -O install.sh https://raw.githubusercontent.com/himik19872/openwrt_x86/main/install.sh

# 2. Запустить установку
sh install.sh
```

Скрипт установит всё необходимое и настроит автозапуск.

---

## 🔧 Ручная установка

### 1. Установка Asterisk 20 и компонентов

```bash
opkg update
opkg install \
  asterisk asterisk-chan-sip asterisk-chan-rtp \
  asterisk-app-mixmonitor asterisk-res-monitor \
  asterisk-res-rtp-asterisk asterisk-res-pjproject \
  asterisk-codec-a-mu asterisk-codec-alaw asterisk-codec-ulaw \
  asterisk-codec-g722 asterisk-codec-gsm asterisk-codec-resample \
  asterisk-format-pcm asterisk-format-sln asterisk-format-wav \
  asterisk-format-h264 asterisk-format-h263 \
  asterisk-cdr asterisk-cdr-custom \
  python3 python3-pip ffmpeg
```

### 2. Установка Flask

```bash
pip3 install flask werkzeug
```

### 3. Копирование файлов

```bash
# Файлы Asterisk Monitor
mkdir -p /usr/lib/asterisk-monitor/{templates,static}
mkdir -p /var/spool/asterisk/monitor
mkdir -p /var/log/asterisk/cdr-custom

# Скопируйте содержимое asterisk-monitor/app/ в /usr/lib/asterisk-monitor/
# Скопируйте asterisk-monitor/asterisk-conf/* в /etc/asterisk/
# Скопируйте asterisk-monitor/luci/* в соответствующие каталоги
```

### 4. Запуск

```bash
# Запуск Asterisk
/etc/init.d/asterisk restart

# Запуск веб-монитора
cd /usr/lib/asterisk-monitor && python3 app.py &
```

### 5. Интеграция с LuCI

Файлы в `asterisk-monitor/luci/` нужно скопировать:
- `menu.d/*.json` → `/usr/share/luci/menu.d/`
- `view/*.js` → `/www/luci-static/resources/view/`
- `cgi-bin/*` → `/www/cgi-bin/`

После этого в меню OpenWrt **Services** появятся пункты **Asterisk Monitor** и **go2rtc**.

---

## 📂 Структура репозитория

```
openwrt-x86/
├── install.sh                              # Универсальный установщик
├── README.md                               # Этот файл
├── asterisk-monitor/
│   ├── app/
│   │   ├── app.py                          # Flask веб-приложение
│   │   ├── config.json                     # Конфиг (пароль по умолчанию)
│   │   ├── templates/
│   │   │   ├── login.html                  # Страница входа
│   │   │   ├── dashboard.html              # Дашборд + записи
│   │   │   └── settings.html               # Настройки
│   │   └── static/
│   │       └── cascade.css                 # Тёмная тема
│   ├── asterisk-conf/
│   │   ├── extensions.conf                 # Диалплан с MixMonitor
│   │   ├── sip.conf                        # 33 SIP-пира + шаблоны
│   │   ├── modules.conf                    # Автозагрузка модулей
│   │   ├── cdr.conf                        # CDR настройки
│   │   └── cdr_custom.conf                 # CSV логирование
│   ├── init/
│   │   ├── cleanup_recordings.sh           # Очистка записей (cron)
│   │   └── asterisk-monitor                # init.d сервис (бонус)
│   └── luci/
│       ├── menu.d/
│       │   ├── luci-app-asterisk-monitor.json
│       │   └── luci-app-go2rtc.json
│       ├── view/
│       │   ├── asterisk-monitor.js
│       │   └── go2rtc.js
│       └── cgi-bin/
│           ├── asterisk-monitor            # CGI редирект → Flask
│           └── go2rtc                      # CGI редирект → go2rtc
└── init-scripts/                           # Дополнительные скрипты
```

---

## 🔌 API Endpoints (Flask)

| Метод | Путь | Описание |
|-------|------|---------|
| GET | `/login` | Страница входа |
| POST | `/login` | Аутентификация |
| GET | `/dashboard` | Главная панель |
| GET | `/settings` | Настройки (смена пароля) |
| GET | `/api/status` | Статус SIP-пиров (JSON) |
| GET | `/api/peers` | Список пиров с деталями |
| POST | `/api/peers` | Создать пир |
| PUT | `/api/peers/<name>` | Обновить пир |
| DELETE | `/api/peers/<name>` | Удалить пир |
| GET | `/api/recordings` | Список записей звонков |
| GET | `/api/recordings/play/<file>` | Прослушать запись |
| POST | `/api/recordings/delete/<file>` | Удалить запись |
| POST | `/api/change-password` | Смена пароля |
| GET | `/api/reload` | Перезагрузить конфиг Asterisk |

---

## 📞 Использование

### Вход
- **URL:** http://192.168.1.1:5000
- **Логин:** `admin`
- **Пароль:** `asterisk123`

### Управление пирами
1. На вкладке **📋 Пиры** отображаются все SIP-пиры со статусом
2. **✏️** — редактировать пир (пароль, тип устройства, CallerID)
3. **🗑️** — удалить пир
4. **➕** — добавить новый пир (номер, пароль, тип)

### Записи звонков
1. Вкладка **🎙 Записи** — все звонки с аудио
2. **▶ Воспр.** — прослушать запись
3. **⬇** — скачать WAV-файл
4. **🗑️** — удалить запись
5. Автоочистка раз в неделю (старше 7 дней)

### Через OpenWrt
- **Меню:** Services → Asterisk Monitor → 📞 Панель управления
- **Прямая ссылка:** http://192.168.1.1/cgi-bin/luci

---

## 🎥 go2rtc

go2rtc — мультипоточный сервер для видеокамер. 
Установленный порт: **1984**.

```bash
# Конфигурация
/etc/go2rtc.yaml

# Веб-интерфейс
http://192.168.1.1:1984
```

Пункт меню: **Services → go2rtc → 📹 Панель управления**

---

## 🧰 Дополнительные сервисы роутера

Кроме домофонии в репозитории есть набор модулей для повседневной эксплуатации роутера — VPN, контроль ИБП, уведомления, GPS-трекинг и управление доменом с поддоменами.

📁 Подробности и установка: **[`router-services/`](router-services/README.md)**

| Модуль | Что делает | Интерфейс |
|---|---|---|
| [**wireguard**](router-services/wireguard/) | WireGuard-сервер + панель: клиенты, QR-коды, `.conf`, вкл/выкл | `http://<router>/wgadmin/` |
| [**ups-nut**](router-services/ups-nut/) | NUT + панель ИБП: заряд, автономия, тест батареи, Telegram | `/cgi-bin/upsadmin?action=ui` |
| [**notify-netmon**](router-services/notify-netmon/) | Telegram-уведомления + мониторинг устройств сети | `/cgi-bin/netmon?action=ui` |
| [**traccar**](router-services/traccar/) | Traccar в Docker + HTTPS через nginx | `:8082`, `https://<domain>:8445` |
| [**dns-domains**](router-services/dns-domains/) | Поддомены DuckDNS wildcard + nginx + dnsmasq + TLS | `https://<sub>.<domain>/` |
| [**common**](router-services/common/) | nginx, карточки LuCI, **фикс hairpin NAT (br_netfilter от Docker)** | LuCI → Сервисы |

Быстрый старт:

```bash
cd /root/openwrt_x86/router-services
sh wireguard/install.sh && sh ups-nut/install.sh && sh notify-netmon/install.sh
sh traccar/install.sh && sh dns-domains/install.sh && sh common/install.sh
```

> ⚠️ Если Docker установлен, пробросы портов перестают работать из локальной сети (hairpin NAT) — причина и исправление в [`docs/TROUBLESHOOTING.md`](router-services/docs/TROUBLESHOOTING.md#1-пробросы-портов-dnat-не-работают-из-локальной-сети-а-из-интернета-работают).

---

## 🚀 TODO / Планы

- [ ] Видео-запись звонков (захват RTP H264)
- [ ] Группы звонков (Ring Groups) через веб-интерфейс
- [ ] Голосовая почта через веб-интерфейс
- [x] Telegram-уведомления о звонках
- [x] Интеграция с Home Assistant через MQTT
- [x] WireGuard Manager — управление клиентами
- [x] ARP Scan — LuCI страница

---

## 📬 Контакты

По вопросам и предложениям — [Issues](https://github.com/himik19872/openwrt_x86/issues)

---

## ⚠️ Важно

- Все пароли по умолчанию **необходимо сменить** после установки!
- Файл `sip.conf` содержит примеры пиров. Замените на свои.
- Для go2rtc требуется отдельная настройка `/etc/go2rtc.yaml`.
- Рекомендуется включить HTTPS для веб-интерфейса.
#!/bin/sh
# ============================================================
# Installer for Asterisk SIP Monitor + go2rtc integration
# for OpenWrt x86_64
# Usage: sh install.sh
# ============================================================

set -e

echo "📞 Установка Asterisk SIP Monitor для OpenWrt"
echo "============================================"

# 1. Проверка архитектуры
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "⚠️  Этот скрипт предназначен для x86_64. Ваша архитектура: $ARCH"
    echo "   Пакеты могут отличаться."
fi

# 2. Обновление списка пакетов
echo ""
echo "🔄 Обновление списка пакетов..."
opkg update >/dev/null 2>&1 || { echo "❌ opkg update failed"; exit 1; }

# 3. Установка зависимостей Asterisk
echo ""
echo "📦 Установка Asterisk 20 и компонентов..."
opkg install \
  asterisk \
  asterisk-chan-sip \
  asterisk-chan-rtp \
  asterisk-app-mixmonitor \
  asterisk-res-monitor \
  asterisk-res-rtp-asterisk \
  asterisk-res-pjproject \
  asterisk-codec-a-mu \
  asterisk-codec-alaw \
  asterisk-codec-ulaw \
  asterisk-codec-g722 \
  asterisk-codec-gsm \
  asterisk-codec-resample \
  asterisk-format-pcm \
  asterisk-format-sln \
  asterisk-format-wav \
  asterisk-format-h264 \
  asterisk-format-h263 \
  asterisk-cdr \
  asterisk-cdr-custom \
  python3 \
  python3-pip \
  ffmpeg \
  2>&1 | grep -E "Configuring|error"

# 4. Установка Python пакетов для Flask
echo ""
echo "🐍 Установка Python-зависимостей..."
pip3 install flask werkzeug 2>&1 | tail -3

# 5. Копирование файлов монитора
echo ""
echo "📂 Копирование файлов Asterisk Monitor..."

# Определяем директорию скрипта
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Создаем целевую директорию
mkdir -p /usr/lib/asterisk-monitor
mkdir -p /usr/lib/asterisk-monitor/templates
mkdir -p /usr/lib/asterisk-monitor/static
mkdir -p /var/spool/asterisk/monitor
mkdir -p /var/log/asterisk/cdr-custom

# Копируем app.py
cp "$SCRIPT_DIR/asterisk-monitor/app/app.py" /usr/lib/asterisk-monitor/
cp "$SCRIPT_DIR/asterisk-monitor/app/config.json" /usr/lib/asterisk-monitor/ 2>/dev/null || true
cp "$SCRIPT_DIR/asterisk-monitor/app/templates/"*.html /usr/lib/asterisk-monitor/templates/
cp "$SCRIPT_DIR/asterisk-monitor/app/static/"* /usr/lib/asterisk-monitor/static/ 2>/dev/null || true

# Копируем конфиги Asterisk
cp "$SCRIPT_DIR/asterisk-monitor/asterisk-conf/extensions.conf" /etc/asterisk/
cp "$SCRIPT_DIR/asterisk-monitor/asterisk-conf/sip.conf" /etc/asterisk/
cp "$SCRIPT_DIR/asterisk-monitor/asterisk-conf/modules.conf" /etc/asterisk/
cp "$SCRIPT_DIR/asterisk-monitor/asterisk-conf/cdr_custom.conf" /etc/asterisk/ 2>/dev/null || true
cp "$SCRIPT_DIR/asterisk-monitor/asterisk-conf/cdr.conf" /etc/asterisk/ 2>/dev/null || true

# Копируем init.d скрипт
if [ -f "$SCRIPT_DIR/asterisk-monitor/init/asterisk-monitor" ]; then
    cp "$SCRIPT_DIR/asterisk-monitor/init/asterisk-monitor" /etc/init.d/
    chmod +x /etc/init.d/asterisk-monitor
fi

# Копируем скрипт очистки
cp "$SCRIPT_DIR/asterisk-monitor/init/cleanup_recordings.sh" /usr/lib/asterisk-monitor/
chmod +x /usr/lib/asterisk-monitor/cleanup_recordings.sh

# 6. Копирование LuCI файлов
echo ""
echo "🌐 Установка интеграции с LuCI (OpenWrt Web UI)..."
cp "$SCRIPT_DIR/asterisk-monitor/luci/menu.d/"*.json /usr/share/luci/menu.d/ 2>/dev/null || true
cp "$SCRIPT_DIR/asterisk-monitor/luci/view/"*.js /www/luci-static/resources/view/ 2>/dev/null || true
cp "$SCRIPT_DIR/asterisk-monitor/luci/cgi-bin/"* /www/cgi-bin/ 2>/dev/null || true
chmod +x /www/cgi-bin/asterisk-monitor /www/cgi-bin/go2rtc 2>/dev/null || true

# 7. Настройка прав
echo ""
echo "🔧 Настройка прав доступа..."
chown -R asterisk:asterisk /var/spool/asterisk/monitor 2>/dev/null || true
chown -R asterisk:asterisk /var/log/asterisk/cdr-custom 2>/dev/null || true
chmod 755 /usr/lib/asterisk-monitor
chmod 755 /usr/lib/asterisk-monitor/app.py

# 8. Настройка автозапуска Asterisk
echo ""
echo "⚙️  Настройка автозапуска..."
/etc/init.d/asterisk enable 2>/dev/null || true

# 9. Добавление cron для очистки записей
echo ""
echo "🕐 Настройка cron для очистки записей (каждое воскресенье 3:00)..."
(crontab -l 2>/dev/null | grep -v "cleanup_recordings"; echo "0 3 * * 7 /usr/lib/asterisk-monitor/cleanup_recordings.sh") | crontab - 2>/dev/null || true

# 10. Запуск сервисов
echo ""
echo "▶️  Запуск Asterisk..."
/etc/init.d/asterisk restart 2>/dev/null || asterisk 2>/dev/null &
sleep 3

echo ""
echo "▶️  Запуск Asterisk Monitor (Flask)..."
cd /usr/lib/asterisk-monitor && python3 app.py > /tmp/asterisk-monitor.log 2>&1 &
sleep 2

echo ""
echo "✅ Установка завершена!"
echo ""
echo "============================================"
echo "Ссылки:"
echo "  📞 Asterisk Monitor: http://192.168.1.1:5000"
echo "  📹 go2rtc:          http://192.168.1.1:1984"
echo "  🌐 OpenWrt LuCI:    http://192.168.1.1/cgi-bin/luci"
echo "  → Services → Asterisk Monitor → 📞 Панель управления"
echo "  → Services → go2rtc → 📹 Панель управления"
echo "============================================"
echo ""
echo "📌 Логин: admin    Пароль: asterisk123"
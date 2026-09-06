#!/usr/bin/env python3
"""
Asterisk SIP Monitor for OpenWrt
Web interface for managing SIP peers, ring groups, voicemail
"""

import re, os, json, subprocess, hashlib
from datetime import datetime
from functools import wraps
from flask import Flask, render_template, jsonify, request, redirect, url_for, session

try:
    from werkzeug.security import generate_password_hash, check_password_hash
except ImportError:
    pass

# ============================================================
# CONFIG
# ============================================================
APP_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(APP_DIR, 'config.json')
SIP_CONF = '/etc/asterisk/sip.conf'
ASTERISK_BIN = '/usr/sbin/asterisk'

app = Flask(__name__)
app.secret_key = hashlib.sha256(b'asterisk-monitor-openwrt-secret').hexdigest()

# ============================================================
# MANUFACTURER TEMPLATES
# ============================================================
MANUFACTURERS = {
    'beward':    {'label': '🚪 Beward', 'type': 'peer', 'context': 'call-panels', 'dtmfmode': 'info', 'directmedia': 'no', 'qualifyfreq': 120, 'allow': ['ulaw','alaw','g722','h264','h263']},
    'dahua':     {'label': '🚪 Dahua', 'type': 'peer', 'context': 'call-panels', 'dtmfmode': 'info', 'directmedia': 'no', 'insecure': 'port,invite', 'qualifyfreq': 120, 'allow': ['ulaw','alaw','g722','h264','h263']},
    'rubitek':   {'label': '🚪 Rubitek', 'type': 'peer', 'context': 'call-panels', 'dtmfmode': 'info', 'directmedia': 'no', 'insecure': 'port,invite', 'qualifyfreq': 120, 'allow': ['ulaw','alaw','g722','h264','h263']},
    'openipc':   {'label': '🚪 OpenIPC', 'type': 'peer', 'context': 'call-panels', 'dtmfmode': 'rfc2833', 'directmedia': 'yes', 'insecure': 'port,invite', 'qualifyfreq': 120, 'allow': ['ulaw','alaw','g722','h264','h263']},
    'apartment': {'label': '🏠 Квартира', 'type': 'friend', 'context': 'apartments', 'dtmfmode': 'rfc2833', 'directmedia': 'yes', 'insecure': 'port,invite', 'qualifyfreq': 60, 'allow': ['ulaw','alaw','g722','h264','h263']},
    'other':     {'label': '📱 Другое', 'type': 'friend', 'context': 'default', 'dtmfmode': 'rfc2833', 'directmedia': 'no', 'qualifyfreq': 60, 'allow': ['ulaw','alaw','h264','h263']},
}
VALID_DEVICE_TYPES = list(MANUFACTURERS.keys())

DEFAULT_CONFIG = {
    "admin_username": "admin",
    "admin_password_hash": generate_password_hash("asterisk123"),
    "sip_peers": [],
    "ring_groups": [],
    "voicemail_boxes": [],
}

# ============================================================
# HELPERS
# ============================================================
def load_config():
    if not os.path.exists(CONFIG_FILE):
        save_config(DEFAULT_CONFIG)
        return dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_FILE) as f: return json.load(f)
    except: return dict(DEFAULT_CONFIG)

def save_config(config):
    with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)
    os.chmod(CONFIG_FILE, 0o600)

def run_asterisk(cmd):
    try:
        r = subprocess.run([ASTERISK_BIN, '-rx', cmd], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else f"Error: {r.stderr}"
    except Exception as e: return f"Error: {str(e)}"

def read_file(path):
    try:
        with open(path) as f: return f.read()
    except: return ""

def write_file(path, content):
    try:
        with open(path, 'w') as f: f.write(content)
        return True
    except: return False

# ============================================================
# SIP CONFIG PARSING
# ============================================================
def parse_sip_conf():
    sections = []
    content = read_file(SIP_CONF)
    if not content: return sections
    cur = None; cur_lines = []; in_tmpl = False; refs = []
    for line in content.split('\n'):
        m = re.match(r'^\[([^\]]+)\]', line.strip())
        if m:
            if cur: sections.append({'name': cur, 'config_lines': cur_lines, 'is_template': in_tmpl, 'template_refs': refs})
            name = m.group(1); rest = line[len(m.group(0)):].strip()
            in_tmpl = '(!)' in rest
            t = [r.replace('!','') for r in re.findall(r'\(([^)]+)\)', rest) if r != '!' and not r.startswith('!')]
            cur = name; cur_lines = [line]; refs = t
        elif cur: cur_lines.append(line)
    if cur: sections.append({'name': cur, 'config_lines': cur_lines, 'is_template': in_tmpl, 'template_refs': refs})
    return sections

def get_sip_peers():
    peers = []
    for s in parse_sip_conf():
        if s['is_template'] or s['name'].lower() in ('general','authentication','globals'): continue
        p = {'name': s['name'], 'secret': '', 'type': 'friend', 'host': 'dynamic', 'context': '', 'callerid': '',
             'dtmfmode': 'rfc2833', 'directmedia': 'no', 'nat': '', 'qualify': 'yes', 'allow': [],
             'device_type': 'other', 'device_label': '📱 Другое'}
        for line in s['config_lines']:
            if '=' not in line: continue
            k, _, v = line.strip().partition('='); k = k.strip().lower(); v = v.strip()
            if k == 'secret': p['secret'] = v
            elif k == 'type': p['type'] = v
            elif k == 'host': p['host'] = v
            elif k == 'context': p['context'] = v
            elif k == 'callerid': p['callerid'] = v
            elif k == 'dtmfmode': p['dtmfmode'] = v
            elif k == 'directmedia': p['directmedia'] = v
            elif k == 'nat': p['nat'] = v
            elif k == 'qualify': p['qualify'] = v
            elif k == 'allow': p['allow'].append(v)
        # Определяем тип по номеру
        if p['name'].isdigit():
            n = int(p['name'])
            if n == 100: p['device_type'] = 'dahua'
            elif n == 101: p['device_type'] = 'beward'
            elif 102 <= n <= 110: p['device_type'] = 'openipc'
            elif 111 <= n <= 130: p['device_type'] = 'apartment'
        p['device_label'] = MANUFACTURERS.get(p['device_type'], {}).get('label', '📱 Другое')
        peers.append(p)
    return peers

def generate_sip_conf(peers):
    lines = [
        '; sip.conf - Auto-generated by Asterisk SIP Monitor',
        f'; Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}',
        '',
        '[general]', 'context=default', 'allowoverlap=no', 'udpbindaddr=0.0.0.0',
        'tcpenable=no', 'transport=udp', 'srvlookup=yes', 'callcounter=yes',
        'session-timers=refuse', 'videosupport=yes', 'dtmfmode=rfc2833',
        'disallow=all', 'allow=ulaw', 'allow=alaw', 'allow=h264', 'allow=h263',
        'nat=force_rport,comedia', 'directmedia=no', 'qualify=yes', 'qualifyfreq=60',
        'alwaysauthreject=yes', 'useragent=Asterisk-OpenWrt', 'mohinterpret=default', 'mohsuggest=default',
        '',
        ';========== TEMPLATES ==========', '',
    ]
    for mt, mc in MANUFACTURERS.items():
        if mt == 'other': continue
        tname = mt + '-panel' if mt != 'apartment' else 'apartment'
        lines.append(f'[{tname}](!)')
        lines.append(f'type={mc["type"]}'); lines.append('host=dynamic')
        lines.append(f'context={mc["context"]}'); lines.append(f'dtmfmode={mc["dtmfmode"]}')
        lines.append('videosupport=yes'); lines.append(f'directmedia={mc["directmedia"]}')
        if mc.get('insecure'): lines.append(f'insecure={mc["insecure"]}')
        lines.append('qualify=yes'); lines.append(f'qualifyfreq={mc["qualifyfreq"]}')
        lines.append('disallow=all')
        for c in mc['allow']: lines.append(f'allow={c}')
        lines.append('nat=force_rport,comedia'); lines.append('mohinterpret=default'); lines.append('mohsuggest=default')
        lines.append('')
    lines.append('[other](!)')
    lines.append('type=friend'); lines.append('host=dynamic'); lines.append('context=default')
    lines.append('dtmfmode=rfc2833'); lines.append('directmedia=no'); lines.append('qualify=yes')
    lines.append('qualifyfreq=60'); lines.append('disallow=all')
    lines.append('allow=ulaw'); lines.append('allow=alaw'); lines.append('allow=h264'); lines.append('allow=h263')
    lines.append('nat=force_rport,comedia'); lines.append('')

    lines.append(';========== SIP PEERS ==========')
    lines.append('')
    for p in sorted(peers, key=lambda x: x.get('name','')):
        dt = p.get('device_type', 'other')
        tpl = 'apartment' if dt == 'apartment' else (dt + '-panel' if dt != 'other' else 'other')
        lines.append(f'[{p["name"]}]({tpl})')
        if p.get('secret'): lines.append(f'secret={p["secret"]}')
        if p.get('host') and p['host'] != 'dynamic': lines.append(f'host={p["host"]}')
        if p.get('callerid'): lines.append(f'callerid={p["callerid"]}')
        m = MANUFACTURERS.get(dt)
        if m: lines.append(f'directmedia={m["directmedia"]}'); lines.append('videosupport=yes')
        lines.append('')
    return '\n'.join(lines)

# ============================================================
# EXTENSIONS CONFIG
# ============================================================
def generate_extensions_conf(peers, ring_groups):
    lines = [
        '; extensions.conf - Auto-generated by Asterisk SIP Monitor',
        f'; Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}',
        '',
        '[general]', 'static=yes', 'writeprotect=no', 'autofallthrough=yes', 'clearglobalvars=yes',
        '',
        '[globals]',
        'RECORDING_DIR=/var/spool/asterisk/monitor',
        '',
        '[default]',
        'exten => _X.,1,NoOp(Unknown call to ${EXTEN})',
        ' same => n,MixMonitor(${RECORDING_DIR}/${UNIQUEID}.wav,b)',
        ' same => n,Hangup()',
        '',
        '[call-panels]',
        '; Вызывные панели (подъезды)',
        'exten => _XXX,1,MixMonitor(${RECORDING_DIR}/${UNIQUEID}.wav,b)',
        ' same => n,Dial(SIP/${EXTEN},60,r)',
        ' same => n,Hangup()',
        '',
        '[apartments]',
        '; Квартиры',
        'exten => _XXX,1,MixMonitor(${RECORDING_DIR}/${UNIQUEID}.wav,b)',
        ' same => n,Dial(SIP/${EXTEN},60,r)',
        ' same => n,Voicemail(${EXTEN},u)',
        ' same => n,Hangup()',
        '',
    ]
    if ring_groups:
        lines.append(';========== RING GROUPS ==========')
        lines.append('')
        for g in ring_groups:
            num = g.get('number', '')
            members = g.get('members', [])
            strategy = g.get('strategy', 'ring-all')
            timeout = g.get('timeout', 30)
            if not num: continue
            if strategy == 'ring-all':
                member_str = "/".join(members)
                lines.append(f'exten => {num},1,Dial(SIP/{member_str},{timeout},r)')
            elif strategy == 'sequential':
                lines.append(f'exten => {num},1,Dial(SIP/{members[0]},{timeout},r)')
                for i, m in enumerate(members[1:], 2):
                    lines.append(f' same => n,Dial(SIP/{m},{timeout},r)')
            lines.append(f' same => n,Hangup()')
            lines.append('')
    return '\n'.join(lines)

# ============================================================
# SIP STATUS
# ============================================================
def get_sip_summary():
    output = run_asterisk("sip show peers")
    # Get detailed peer configs for device type info
    peer_configs = {p['name']: p for p in get_sip_peers()}
    peers = []
    for line in output.split('\n'):
        if not line.strip() or 'sip peers' in line or 'Name/username' in line: continue
        m = re.match(r'^([\w\.-]+)', line)
        if not m: continue
        name = m.group(1).split('/')[0]  # Отделяем имя от username
        if not name or name.isdigit() == False: continue
        # Статус - ищем OK в последних 30 символах или UNKNOWN
        status_part = line[90:].strip() if len(line) > 90 else line[-30:].strip()
        is_online = 'OK' in status_part
        latency = None
        lm = re.search(r'\((\d+)\s*ms\)', line)
        if lm: latency = int(lm.group(1))
        host = line[25:67].strip() if len(line) > 67 else '(Unspecified)'
        if host == '(Unspecified)': host = '(Unspecified)'
        # Add device type from config
        cfg = peer_configs.get(name, {})
        device_type = cfg.get('device_type', 'other')
        device_label = cfg.get('device_label', MANUFACTURERS['other']['label'])
        peers.append({'name': name, 'is_online': is_online, 'latency': latency,
                      'host': host, 'device_type': device_type, 'device_label': device_label})
    total = len(peers); online = sum(1 for p in peers if p['is_online'])
    return {"peers": peers, "total": total, "online": online, "offline": total - online}

# ============================================================
# APPLY CONFIG
# ============================================================
def apply_sip_config(peers, ring_groups=None):
    try:
        sip_text = generate_sip_conf(peers)
        ext_text = generate_extensions_conf(peers, ring_groups or [])
        if not write_file(SIP_CONF, sip_text): return False, "Cannot write sip.conf"
        if not write_file('/etc/asterisk/extensions.conf', ext_text): return False, "Cannot write extensions.conf"
        r1 = run_asterisk("module reload chan_sip.so")
        r2 = run_asterisk("dialplan reload")
        if 'Error' in r1: return False, f"Reload error: {r1}"
        return True, "Configuration applied"
    except Exception as e: return False, f"Error: {str(e)}"

# ============================================================
# AUTH
# ============================================================
def login_required(f):
    @wraps(f)
    def decorated(*a, **kw):
        if not session.get('logged_in'): return redirect(url_for('login'))
        return f(*a, **kw)
    return decorated

# ============================================================
# ROUTES
# ============================================================
@app.route('/login', methods=['GET','POST'])
def login():
    if session.get('logged_in'): return redirect(url_for('dashboard'))
    error = None
    if request.method == 'POST':
        cfg = load_config()
        if request.form.get('username') == cfg.get('admin_username') and check_password_hash(cfg.get('admin_password_hash',''), request.form.get('password','')):
            session['logged_in'] = True; session['admin_username'] = request.form.get('username')
            return redirect(url_for('dashboard'))
        else: error = 'Неверное имя или пароль'
    return render_template('login.html', error=error)

@app.route('/logout')
def logout(): session.clear(); return redirect(url_for('login'))

@app.route('/')
def index(): return redirect(url_for('login'))

@app.route('/dashboard')
@login_required
def dashboard(): return render_template('dashboard.html', page='dashboard', username=session.get('admin_username'))

@app.route('/settings')
@login_required
def settings_page(): return render_template('settings.html', page='settings', username=session.get('admin_username'))

@app.route('/api/status')
@login_required
def api_status(): return jsonify(get_sip_summary())

@app.route('/api/peers')
@login_required
def api_get_peers(): return jsonify({"peers": get_sip_peers(), "total": 0})

@app.route('/api/peers', methods=['POST'])
@login_required
def api_add_peer():
    data = request.get_json()
    if not data or not data.get('name') or not data.get('secret'): return jsonify({"error": "Name and secret required"}), 400
    name = data['name'].strip()
    if not re.match(r'^[a-zA-Z0-9_-]+$', name): return jsonify({"error": "Invalid name"}), 400
    peers = get_sip_peers()
    if any(p['name'] == name for p in peers): return jsonify({"error": "Already exists"}), 409
    dt = data.get('device_type', 'other')
    if dt not in VALID_DEVICE_TYPES: dt = 'other'
    peers.append({'name': name, 'secret': data['secret'], 'host': data.get('host','dynamic'), 'context': data.get('context',''),
                  'callerid': data.get('callerid',''), 'dtmfmode': data.get('dtmfmode','rfc2833'), 'directmedia': data.get('directmedia','no'),
                  'device_type': dt, 'device_label': MANUFACTURERS[dt]['label'], 'allow': data.get('allow',[])})
    cfg = load_config()
    s, m = apply_sip_config(peers, cfg.get('ring_groups'))
    if s: return jsonify({"success": True, "message": m})
    return jsonify({"error": m}), 500

@app.route('/api/peers/<name>', methods=['GET'])
@login_required
def api_get_peer(name):
    peers = get_sip_peers()
    for p in peers:
        if p['name'] == name:
            return jsonify(p)
    return jsonify({"error": "Not found"}), 404

@app.route('/api/peers/<name>', methods=['DELETE'])
@login_required
def api_delete_peer(name):
    peers = [p for p in get_sip_peers() if p['name'] != name]
    if len(peers) == len(get_sip_peers()): return jsonify({"error": "Not found"}), 404
    cfg = load_config()
    s, m = apply_sip_config(peers, cfg.get('ring_groups'))
    if s: return jsonify({"success": True, "message": m})
    return jsonify({"error": m}), 500

@app.route('/api/peers/<name>', methods=['PUT'])
@login_required
def api_update_peer(name):
    data = request.get_json()
    if not data: return jsonify({"error": "No data"}), 400
    peers = get_sip_peers()
    for p in peers:
        if p['name'] == name:
            for k in ['secret','host','context','callerid','dtmfmode','directmedia','device_type']:
                if k in data: p[k] = data[k]
            if 'device_type' in data and data['device_type'] in VALID_DEVICE_TYPES:
                p['device_label'] = MANUFACTURERS[data['device_type']]['label']
            cfg = load_config()
            s, m = apply_sip_config(peers, cfg.get('ring_groups'))
            if s: return jsonify({"success": True, "message": m})
            return jsonify({"error": m}), 500
    return jsonify({"error": "Not found"}), 404

@app.route('/api/change-password', methods=['POST'])
@login_required
def api_change_password():
    data = request.get_json()
    cfg = load_config()
    if not check_password_hash(cfg['admin_password_hash'], data.get('current_password','')): return jsonify({"error": "Wrong password"}), 403
    if not data.get('new_password') or len(data['new_password']) < 4: return jsonify({"error": "Min 4 chars"}), 400
    if data['new_password'] != data.get('confirm_password'): return jsonify({"error": "Passwords don't match"}), 400
    cfg['admin_password_hash'] = generate_password_hash(data['new_password'])
    save_config(cfg)
    return jsonify({"success": True, "message": "Password changed"})

@app.route('/api/reload')
@login_required
def api_reload():
    cfg = load_config()
    peers = get_sip_peers()
    s, m = apply_sip_config(peers, cfg.get('ring_groups'))
    return jsonify({"success": s, "message": m})

@app.route('/api/groups')
@login_required
def api_get_groups():
    cfg = load_config()
    return jsonify({"groups": cfg.get('ring_groups', [])})

@app.route('/api/groups', methods=['POST'])
@login_required
def api_add_group():
    data = request.get_json()
    if not data or not data.get('number'): return jsonify({"error": "Number required"}), 400
    cfg = load_config(); groups = cfg.get('ring_groups', [])
    if any(g['number'] == data['number'] for g in groups): return jsonify({"error": "Exists"}), 409
    if not data.get('members') or len(data['members']) < 1: return jsonify({"error": "At least 1 member"}), 400
    groups.append({'number': data['number'], 'name': data.get('name',''), 'members': data['members'],
                   'timeout': int(data.get('timeout',30)), 'strategy': data.get('strategy','ring-all')})
    cfg['ring_groups'] = groups; save_config(cfg)
    s, m = apply_sip_config(get_sip_peers(), groups)
    if s: return jsonify({"success": True, "message": m})
    return jsonify({"error": m}), 500

@app.route('/api/groups/<number>', methods=['DELETE'])
@login_required
def api_delete_group(number):
    cfg = load_config(); groups = [g for g in cfg.get('ring_groups',[]) if g['number'] != number]
    cfg['ring_groups'] = groups; save_config(cfg)
    s, m = apply_sip_config(get_sip_peers(), groups)
    return jsonify({"success": s, "message": m})

@app.route('/api/voicemail/boxes')
@login_required
def api_get_voicemail():
    cfg = load_config()
    return jsonify({"boxes": cfg.get('voicemail_boxes', [])})

@app.route('/api/voicemail/boxes', methods=['POST'])
@login_required
def api_add_voicemail():
    data = request.get_json()
    cfg = load_config(); boxes = cfg.get('voicemail_boxes', [])
    if not data or not data.get('mailbox'): return jsonify({"error": "Mailbox required"}), 400
    if any(b['mailbox'] == data['mailbox'] for b in boxes): return jsonify({"error": "Exists"}), 409
    boxes.append({'mailbox': data['mailbox'], 'password': data.get('password','1234'), 'name': data.get('name',''), 'email': data.get('email','')})
    cfg['voicemail_boxes'] = boxes; save_config(cfg)
    return jsonify({"success": True, "message": "Voicemail box added"})

@app.route('/api/voicemail/boxes/<mailbox>', methods=['DELETE'])
@login_required
def api_delete_voicemail(mailbox):
    cfg = load_config(); cfg['voicemail_boxes'] = [b for b in cfg.get('voicemail_boxes',[]) if b['mailbox'] != mailbox]
    save_config(cfg)
    return jsonify({"success": True, "message": "Deleted"})

# ============================================================
# RECORDINGS
# ============================================================
RECORDINGS_DIR = '/var/spool/asterisk/monitor'
CDR_CSV_PATH = '/var/log/asterisk/cdr-custom/Master.csv'

def load_cdr_cache():
    """Load CDR entries from CSV: uniqueid -> (src, dst, duration, disposition)"""
    cache = {}
    if not os.path.exists(CDR_CSV_PATH):
        return cache
    try:
        import csv
        with open(CDR_CSV_PATH, newline='') as f:
            for row in csv.reader(f):
                if len(row) < 3:
                    continue
                # Detect format: if last col has '.' it's uniqueid, not duration
                # Format A (7 cols): date,src,dst,dur,billsec,disposition,uniqueid
                # Format B (4 cols): date,src,dst,uniqueid
                # Format C (3 cols): epoch,src,dst
                uid = row[-1].strip()
                src = row[1].strip() if len(row) > 1 else '?'
                dst = row[2].strip() if len(row) > 2 else '?'
                
                if len(row) >= 7:
                    # Full format: date, src, dst, duration, billsec, disposition, uniqueid
                    dur = row[3].strip()
                    disp = row[5].strip()
                    date = row[0].strip()
                elif len(row) == 4 and '.' in row[-1]:
                    # Old format: date, src, dst, uniqueid (no duration)
                    dur = '0'
                    disp = 'ANSWERED'
                    date = row[0].strip()
                else:
                    # Minimal
                    dur = '0'
                    disp = 'ANSWERED'
                    date = row[0].strip() if len(row) > 0 else ''
                
                if uid:
                    cache[uid] = {
                        'src': src, 'dst': dst,
                        'duration': dur,
                        'disposition': disp,
                        'date': date,
                    }
    except Exception:
        pass
    return cache

# Load CDR cache on startup
_cdr_cache = load_cdr_cache()

def get_recording_info(filepath):
    """Get recording metadata from filename and CDR."""
    global _cdr_cache
    fname = os.path.basename(filepath)
    uid = os.path.splitext(fname)[0]
    
    # Refresh cache if not found
    cdr = _cdr_cache.get(uid)
    if not cdr:
        _cdr_cache = load_cdr_cache()
        cdr = _cdr_cache.get(uid)
    
    stat = os.stat(filepath)
    size = stat.st_size
    duration_sec = 0
    if cdr and cdr.get('duration'):
        try: duration_sec = int(float(cdr['duration']))
        except: pass
    
    src = (cdr.get('src') or '') if cdr else ''
    dst = (cdr.get('dst') or '') if cdr else ''
    date_val = cdr.get('date', '') if cdr else ''
    disp = cdr.get('disposition', '') if cdr else ''
    
    if not date_val:
        date_val = datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M')
    
    return {
        'filename': fname,
        'path': filepath,
        'size': size,
        'size_str': format_size(size),
        'src': src if src else '?',
        'dst': dst if dst else '?',
        'duration': duration_sec,
        'duration_str': f'{duration_sec//60}:{duration_sec%60:02d}' if duration_sec else '—',
        'date': date_val,
        'disposition': disp if disp else '?',
    }

def format_size(bytes):
    if bytes < 1024: return f'{bytes} B'
    elif bytes < 1024*1024: return f'{bytes/1024:.1f} KB'
    else: return f'{bytes/(1024*1024):.1f} MB'

def get_recordings():
    recordings = []
    if not os.path.isdir(RECORDINGS_DIR):
        return recordings
    try:
        for f in sorted(os.listdir(RECORDINGS_DIR), reverse=True):
            fp = os.path.join(RECORDINGS_DIR, f)
            if os.path.isfile(fp) and f.endswith('.wav'):
                recordings.append(get_recording_info(fp))
    except Exception:
        pass
    return recordings

@app.route('/recordings')
@login_required
def recordings_page():
    return render_template('dashboard.html', page='dashboard', username=session.get('admin_username'))

@app.route('/api/recordings')
@login_required
def api_get_recordings():
    return jsonify({"recordings": get_recordings()})

@app.route('/api/recordings/play/<path:filename>')
@login_required
def api_play_recording(filename):
    safe = os.path.basename(filename)
    filepath = os.path.join(RECORDINGS_DIR, safe)
    if not os.path.exists(filepath):
        return jsonify({"error": "Not found"}), 404
    return open(filepath, 'rb').read(), 200, {'Content-Type': 'audio/wav', 'Content-Disposition': f'inline; filename="{safe}"'}

@app.route('/api/recordings/delete/<path:filename>', methods=['POST'])
@login_required
def api_delete_recording(filename):
    safe = os.path.basename(filename)
    filepath = os.path.join(RECORDINGS_DIR, safe)
    try:
        os.remove(filepath)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ============================================================
# MAIN
# ============================================================
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
#!/bin/bash
# ============================================
# Hapi 4: Monitoring & Health Checks
# Ekzekutohet si user 'openclaw'
# ============================================
set -euo pipefail

echo "=========================================="
echo "  Monitoring Setup - Hapi 4"
echo "=========================================="

GREEN='\033[0;32m'
NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# Ngarko .env nëse ekziston
if [ -f /home/openclaw/.openclaw/.env ]; then
    set -a
    source /home/openclaw/.openclaw/.env
    set +a
fi

# --- 1. Health Check Script ---
echo ""
echo ">>> Krijim i health check script..."
mkdir -p /home/openclaw/scripts

cat > /home/openclaw/scripts/health-check.sh << 'HCEOF'
#!/bin/bash
# Health check — kontrollon çdo 5 minuta
OPENCLAW_PORT=${OPENCLAW_PORT:-18789}
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_ADMIN_CHAT_ID="${TELEGRAM_ADMIN_CHAT_ID}"
LOG_FILE="/home/openclaw/logs/health-check.log"
ALERT_COOLDOWN_FILE="/tmp/openclaw_alert_sent"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

send_telegram() {
    local message="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_ADMIN_CHAT_ID" ]; then
        curl -s -X POST \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_ADMIN_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" > /dev/null 2>&1
    fi
}

# Kontrollo OpenClaw
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:${OPENCLAW_PORT}/health" \
    --connect-timeout 5 \
    --max-time 10 2>/dev/null || echo "000")

if [ "$RESPONSE" = "200" ]; then
    log "[OK] OpenClaw funksionon (HTTP $RESPONSE)"
    # Fshi alert cooldown nëse ekziston
    rm -f "$ALERT_COOLDOWN_FILE"
else
    log "[GABIM] OpenClaw nuk përgjigjet (HTTP $RESPONSE)"

    # Dërgo alert vetëm 1 herë në 30 min
    if [ ! -f "$ALERT_COOLDOWN_FILE" ] || [ "$(find "$ALERT_COOLDOWN_FILE" -mmin +30 2>/dev/null)" ]; then
        send_telegram "⚠️ <b>ALARM:</b> OpenClaw nuk përgjigjet!
Kodi HTTP: $RESPONSE
Serveri: $(hostname)
Ora: $(TZ=Europe/Tirane date '+%H:%M %d.%m.%Y')

Komanda për ta rikthyer:
<code>sudo systemctl restart openclaw</code>"
        touch "$ALERT_COOLDOWN_FILE"
        log "[ALERT] Njoftim dërguar në Telegram"
    fi

    # Provo restart automatik
    if systemctl is-active --quiet openclaw; then
        log "[INFO] Shërbimi aktiv por nuk përgjigjet. Duke pritur..."
    else
        log "[INFO] Duke rifilluar OpenClaw..."
        sudo systemctl restart openclaw
    fi
fi

# Kontrollo hapësirën e diskut
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -gt 85 ]; then
    log "[KUJDES] Disku $DISK_USAGE% i mbushur"
    send_telegram "⚠️ <b>Disku:</b> $DISK_USAGE% i përdorur në $(hostname)"
fi

# Kontrollo RAM
MEM_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2*100}')
if [ "$MEM_USAGE" -gt 90 ]; then
    log "[KUJDES] RAM $MEM_USAGE% e përdorur"
    send_telegram "⚠️ <b>RAM:</b> $MEM_USAGE% e përdorur në $(hostname)"
fi
HCEOF

chmod +x /home/openclaw/scripts/health-check.sh
ok "Health check script u krijua"

# --- 2. Shto në crontab (çdo 5 minuta) ---
echo ""
echo ">>> Konfigurim i crontab..."
(crontab -l 2>/dev/null | grep -v "health-check.sh"; echo "*/5 * * * * /home/openclaw/scripts/health-check.sh") | crontab -
ok "Health check çdo 5 minuta (crontab)"

# --- 3. Status script ---
echo ""
echo ">>> Krijim i status script..."
cat > /home/openclaw/scripts/status.sh << 'STEOF'
#!/bin/bash
# Shiko statusin e plotë të sistemit
echo "=========================================="
echo "  OpenClaw System Status"
echo "  $(TZ=Europe/Tirane date '+%H:%M %d.%m.%Y')"
echo "=========================================="
echo ""
echo "--- OpenClaw Service ---"
systemctl is-active openclaw && echo "Statusi: AKTIV" || echo "Statusi: JOAKTIV"
echo ""
echo "--- Docker ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker: Jo aktiv"
echo ""
echo "--- Burimet ---"
echo "RAM:  $(free -h | awk 'NR==2 {print $3"/"$2}')"
echo "CPU:  $(uptime | awk -F'load average:' '{print $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')"
echo ""
echo "--- Rrjeti ---"
echo "UFW:  $(sudo ufw status | head -1)"
echo "f2b:  $(sudo fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' || echo 'N/A')"
echo ""
echo "--- Logs (5 të fundit) ---"
tail -5 /home/openclaw/logs/openclaw.log 2>/dev/null || echo "Asnjë log"
echo "=========================================="
STEOF

chmod +x /home/openclaw/scripts/status.sh
ok "Status script u krijua"

echo ""
echo "=========================================="
echo "  MONITORIMI U KONFIGURUA"
echo "=========================================="
echo "  Health check:  Çdo 5 min (crontab)"
echo "  Alertet:       Via Telegram"
echo "  Status:        ~/scripts/status.sh"
echo "=========================================="

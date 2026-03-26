#!/bin/bash
# ============================================
# Hapi 3: Security Hardening
# Ekzekutohet si user 'openclaw' me sudo
# ============================================
set -euo pipefail

echo "=========================================="
echo "  Security Hardening - Hapi 3"
echo "=========================================="

GREEN='\033[0;32m'
NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# --- 1. Konfiguro fail2ban ---
echo ""
echo ">>> Konfigurim i fail2ban..."
sudo tee /etc/fail2ban/jail.local > /dev/null << 'F2BEOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
F2BEOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
ok "fail2ban u konfigurua (ban 1h pas 3 tentativave)"

# --- 2. Krijo backup script ---
echo ""
echo ">>> Krijim i backup script..."
mkdir -p /home/openclaw/backups

cat > /home/openclaw/scripts/backup.sh << 'BKEOF'
#!/bin/bash
# Backup ditor i OpenClaw workspace
BACKUP_DIR="/home/openclaw/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/openclaw_backup_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Krijo backup
tar -czf "$BACKUP_FILE" \
    -C /home/openclaw \
    .openclaw/workspace \
    .openclaw/openclaw.json \
    2>/dev/null || true

# Fshi backup-et e vjetra
find "$BACKUP_DIR" -name "openclaw_backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete

echo "Backup u krijua: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
BKEOF

chmod +x /home/openclaw/scripts/backup.sh

# Shto në crontab — çdo ditë në 03:00
(crontab -l 2>/dev/null | grep -v "backup.sh"; echo "0 3 * * * /home/openclaw/scripts/backup.sh >> /home/openclaw/logs/backup.log 2>&1") | crontab -
ok "Backup script u krijua (çdo ditë në 03:00)"

# --- 3. Konfiguro sysctl për siguri rrjeti ---
echo ""
echo ">>> Fortifikim i rrjetit..."
sudo tee /etc/sysctl.d/99-openclaw-security.conf > /dev/null << 'SYSEOF'
# Mbroj nga SYN flood
net.ipv4.tcp_syncookies = 1
# Mos lejo IP source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
# Mos lejo ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
# Log paketa martianjësh
net.ipv4.conf.all.log_martians = 1
SYSEOF

sudo sysctl --system > /dev/null 2>&1
ok "Rregullat e sigurisë së rrjetit u aplikuan"

echo ""
echo "=========================================="
echo "  SIGURIA U KONFIGURUA"
echo "=========================================="
echo "  fail2ban:  Aktiv (SSH mbrojtje)"
echo "  Backup:    Ditor në 03:00 → /home/openclaw/backups/"
echo "  Rrjeti:    Fortifikuar (SYN flood, redirects, etc.)"
echo "=========================================="

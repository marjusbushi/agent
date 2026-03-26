#!/bin/bash
# ============================================
# Hapi 1: Setup fillestar i serverit Hetzner
# Ekzekutohet si root në serverin e ri
# ============================================
set -euo pipefail

echo "=========================================="
echo "  OpenClaw Server Setup - Hapi 1"
echo "  Hetzner CX32 / Ubuntu 24.04"
echo "=========================================="

# --- Ngjyra për output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

ok() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[GABIM]${NC} $1"; exit 1; }

# --- 1. Update sistem ---
echo ""
echo ">>> Përditësim i paketave të sistemit..."
apt update && apt upgrade -y
ok "Paketat u përditësuan"

# --- 2. Instalo paketa bazë ---
echo ""
echo ">>> Instalim i paketave bazë..."
apt install -y \
    curl \
    wget \
    git \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    htop \
    tmux \
    jq \
    ca-certificates \
    gnupg \
    lsb-release
ok "Paketat bazë u instaluan"

# --- 3. Krijo user openclaw ---
echo ""
echo ">>> Krijim i përdoruesit 'openclaw'..."
if id "openclaw" &>/dev/null; then
    ok "Përdoruesi 'openclaw' ekziston tashmë"
else
    adduser --disabled-password --gecos "OpenClaw Service" openclaw
    usermod -aG sudo openclaw
    # Lejo sudo pa fjalëkalim për openclaw
    echo "openclaw ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/ufw, /usr/bin/fail2ban-client, /usr/bin/timedatectl" > /etc/sudoers.d/openclaw
    chmod 440 /etc/sudoers.d/openclaw
    ok "Përdoruesi 'openclaw' u krijua me sudo akses"
fi

# --- 4. Kopjo SSH keys tek openclaw ---
echo ""
echo ">>> Konfigurim i SSH keys për 'openclaw'..."
mkdir -p /home/openclaw/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/openclaw/.ssh/authorized_keys
    chown -R openclaw:openclaw /home/openclaw/.ssh
    chmod 700 /home/openclaw/.ssh
    chmod 600 /home/openclaw/.ssh/authorized_keys
    ok "SSH keys u kopjuan tek openclaw"
else
    echo "  KUJDES: Nuk u gjetën SSH keys në /root/.ssh/authorized_keys"
    echo "  Duhet ti shtosh manualisht: ssh-copy-id openclaw@server_ip"
fi

# --- 5. Fortifiko SSH ---
echo ""
echo ">>> Fortifikim i SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
# Backup
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d)"

# Ndryshime sigurie
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"

systemctl restart sshd
ok "SSH u fortifikua (root login OFF, password OFF)"

# --- 6. Konfiguro UFW Firewall ---
echo ""
echo ">>> Konfigurim i UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 18789/tcp comment "OpenClaw Gateway"
echo "y" | ufw enable
ok "UFW u aktivizua (SSH + porta 18789)"

# --- 7. Instalo Docker ---
echo ""
echo ">>> Instalim i Docker..."
if command -v docker &>/dev/null; then
    ok "Docker është tashmë i instaluar"
else
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker openclaw
    systemctl enable docker
    systemctl start docker
    ok "Docker u instalua"
fi

# Verifiko Docker Compose
if docker compose version &>/dev/null; then
    ok "Docker Compose (plugin) gati"
else
    fail "Docker Compose nuk u gjet. Provo: apt install docker-compose-plugin"
fi

# --- 8. Konfiguro unattended-upgrades ---
echo ""
echo ">>> Konfigurim i përditësimeve automatike të sigurisë..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UPGEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UPGEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF
ok "Përditësimet automatike të sigurisë u konfiguruan"

# --- 9. Konfiguro timezone ---
echo ""
echo ">>> Vendosja e timezone..."
timedatectl set-timezone Europe/Tirane
ok "Timezone: Europe/Tirane"

# --- 10. Krijo direktoritë e punës ---
echo ""
echo ">>> Krijim i direktorive..."
mkdir -p /home/openclaw/{workspace,backups,logs}
chown -R openclaw:openclaw /home/openclaw/
ok "Direktorit u krijuan"

# --- Përmbledhje ---
echo ""
echo "=========================================="
echo "  SETUP I PËRFUNDUAR"
echo "=========================================="
echo "  User:      openclaw (me sudo)"
echo "  SSH:       Root disabled, password disabled"
echo "  Firewall:  SSH + porta 18789"
echo "  Docker:    $(docker --version 2>/dev/null || echo 'Gabim')"
echo "  Timezone:  $(timedatectl show -p Timezone --value)"
echo "  Updates:   Automatike (vetëm siguria)"
echo ""
echo "  HAPI TJETËR: Kyçu si openclaw:"
echo "  ssh openclaw@$(hostname -I | awk '{print $1}')"
echo "=========================================="

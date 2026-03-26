#!/bin/bash
# ============================================
# Hapi 2: Instalim i OpenClaw
# Ekzekutohet si user 'openclaw'
# ============================================
set -euo pipefail

echo "=========================================="
echo "  OpenClaw Installation - Hapi 2"
echo "=========================================="

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[GABIM]${NC} $1"; exit 1; }

# --- Verifiko që nuk jemi root ---
if [ "$(whoami)" = "root" ]; then
    fail "Mos ekzekuto si root! Përdor: su - openclaw"
fi

# --- 1. Instalo nvm + Node.js 22 ---
echo ""
echo ">>> Instalim i Node.js 22 via nvm..."
if command -v node &>/dev/null && [[ "$(node -v)" == v2[2-9]* || "$(node -v)" == v2[4-9]* ]]; then
    ok "Node.js $(node -v) gati"
else
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install 22
    nvm use 22
    nvm alias default 22
    ok "Node.js $(node -v) u instalua"
fi

# Sigurohu që nvm është i ngarkuar
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# --- 2. Instalo OpenClaw ---
echo ""
echo ">>> Instalim i OpenClaw..."
if command -v openclaw &>/dev/null; then
    ok "OpenClaw tashmë i instaluar: $(openclaw --version 2>/dev/null || echo 'versioni i panjohur')"
    echo "  Përditësim..."
    npm update -g openclaw
else
    npm install -g openclaw@latest
    ok "OpenClaw u instalua: $(openclaw --version 2>/dev/null || echo 'OK')"
fi

# --- 3. Onboard + Install Daemon ---
echo ""
echo ">>> OpenClaw onboard..."
echo "  KUJDES: Kjo do hapë wizard interaktiv."
echo "  Ndiq hapat në ekran."
echo ""
echo "  Ekzekuto manualisht:"
echo "    openclaw onboard --install-daemon"
echo ""
echo "  Ose nëse do ta bësh non-interaktiv:"
echo "    openclaw onboard --non-interactive --install-daemon"

# --- 4. Krijo systemd service ---
echo ""
echo ">>> Krijim i systemd service..."
sudo tee /etc/systemd/system/openclaw.service > /dev/null << 'SVCEOF'
[Unit]
Description=OpenClaw AI Agent
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw
Environment=HOME=/home/openclaw
Environment=PATH=/home/openclaw/.nvm/versions/node/v22/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=/home/openclaw/.openclaw/.env
ExecStart=/home/openclaw/.nvm/versions/node/v22/bin/openclaw daemon
Restart=always
RestartSec=10
StandardOutput=append:/home/openclaw/logs/openclaw.log
StandardError=append:/home/openclaw/logs/openclaw-error.log

# Kufizime sigurie
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/home/openclaw
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable openclaw.service
ok "Systemd service u krijua dhe u aktivizua"

echo ""
echo "=========================================="
echo "  INSTALIMI I PËRFUNDUAR"
echo "=========================================="
echo "  Node.js:   $(node -v 2>/dev/null || echo 'N/A')"
echo "  OpenClaw:  $(openclaw --version 2>/dev/null || echo 'N/A')"
echo "  Service:   openclaw.service (enabled)"
echo ""
echo "  Komandat:"
echo "    sudo systemctl start openclaw    # Fillo"
echo "    sudo systemctl stop openclaw     # Ndalo"
echo "    sudo systemctl restart openclaw  # Rifillo"
echo "    sudo systemctl status openclaw   # Statusi"
echo "    journalctl -u openclaw -f        # Logat live"
echo "=========================================="

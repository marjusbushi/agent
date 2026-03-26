#!/bin/bash
# ============================================
# Deploy Script — Ngarko gjithçka në server
# Ekzekuto nga kompjuteri yt lokal
# Përdorim: ./scripts/deploy.sh
# ============================================
set -euo pipefail

echo "=========================================="
echo "  OpenClaw Deploy"
echo "=========================================="

# --- Ngarko .env ---
if [ ! -f .env ]; then
    echo "GABIM: Skedari .env nuk u gjet!"
    echo "Kopjo .env.example si .env dhe plotëso vlerat:"
    echo "  cp .env.example .env"
    echo "  nano .env"
    exit 1
fi

set -a
source .env
set +a

SERVER="${OPENCLAW_USER:-openclaw}@${SERVER_IP:?'SERVER_IP duhet vendosur në .env'}"
SSH_PORT="${SSH_PORT:-22}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[GABIM]${NC} $1"; exit 1; }

echo "  Serveri: $SERVER"
echo "  Porta SSH: $SSH_PORT"
echo ""

# --- 1. Testo lidhjen SSH ---
echo ">>> Testim i lidhjes SSH..."
ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$SERVER" "echo 'SSH OK'" || fail "Nuk mund të lidhem me serverin"
ok "Lidhja SSH funksionon"

# --- 2. Krijo struktur direktorish ---
echo ""
echo ">>> Krijim i direktorive në server..."
ssh -p "$SSH_PORT" "$SERVER" "mkdir -p ~/.openclaw/workspace ~/scripts ~/logs ~/backups"
ok "Direktorit u krijuan"

# --- 3. Kopjo skedarët ---
echo ""
echo ">>> Ngarkimi i skedarëve..."

# Config files
scp -P "$SSH_PORT" config/openclaw.json "$SERVER:~/.openclaw/openclaw.json"
scp -P "$SSH_PORT" config/SETTINGS.md "$SERVER:~/.openclaw/workspace/SETTINGS.md"
scp -P "$SSH_PORT" config/HEARTBEAT.md "$SERVER:~/.openclaw/workspace/HEARTBEAT.md"
ok "Konfigurimet u ngarkuan"

# Scripts
scp -P "$SSH_PORT" scripts/01-server-setup.sh "$SERVER:~/scripts/"
scp -P "$SSH_PORT" scripts/02-install-openclaw.sh "$SERVER:~/scripts/"
scp -P "$SSH_PORT" scripts/03-security.sh "$SERVER:~/scripts/"
scp -P "$SSH_PORT" scripts/04-monitoring.sh "$SERVER:~/scripts/"
scp -P "$SSH_PORT" scripts/05-kommo-integration.sh "$SERVER:~/scripts/"
ok "Skriptat u ngarkuan"

# Docker
scp -P "$SSH_PORT" docker/docker-compose.yml "$SERVER:~/docker-compose.yml"
ok "Docker compose u ngarkua"

# .env (KUJDES: përmban sekretet)
scp -P "$SSH_PORT" .env "$SERVER:~/.openclaw/.env"
ok ".env u ngarkua"

# Kommo webhook setup guide
echo ""
echo ">>> Konfigurim i KOMMO_WEBHOOK_PORT në .env..."
ssh -p "$SSH_PORT" "$SERVER" "grep -q 'KOMMO_WEBHOOK_PORT' ~/.openclaw/.env || echo 'KOMMO_WEBHOOK_PORT=18790' >> ~/.openclaw/.env"
ok "KOMMO_WEBHOOK_PORT u shtua"

# --- 4. Bëj skriptat ekzekutueshëm ---
echo ""
echo ">>> Vendosja e lejeve..."
ssh -p "$SSH_PORT" "$SERVER" "chmod +x ~/scripts/*.sh"
ok "Lejet u vendosën"

echo ""
echo "=========================================="
echo "  DEPLOY I PËRFUNDUAR"
echo "=========================================="
echo ""
echo "  Hapat e ardhshëm (në server):"
echo "  1. ssh $SERVER -p $SSH_PORT"
echo "  2. sudo bash ~/scripts/01-server-setup.sh     # Nëse server i ri"
echo "  3. bash ~/scripts/02-install-openclaw.sh       # Instalo OpenClaw"
echo "  4. bash ~/scripts/03-security.sh               # Siguria"
echo "  5. bash ~/scripts/04-monitoring.sh             # Monitorimi"
echo "  6. bash ~/scripts/05-kommo-integration.sh      # Kommo CRM"
echo "  7. sudo systemctl start openclaw               # Fillo shërbimin"
echo ""
echo "  Ose me Docker:"
echo "  docker compose up -d"
echo "=========================================="

#!/bin/bash
# === OpenClaw Rollback Script ===
# Reverts to the previous working state if deployment fails
set -e

OPENCLAW_DIR="/home/openclaw/.openclaw"
BACKUP_DIR="/home/openclaw/backups"
COMPOSE_DIR="/home/openclaw"

echo "=== OpenClaw Rollback ==="

# 1. Stop current containers
echo "[1/4] Stopping containers..."
cd $COMPOSE_DIR && docker compose down 2>/dev/null || true
pkill -9 -f openclaw-gatewa 2>/dev/null || true
sleep 2

# 2. Restore config from backup
if [ -f "$OPENCLAW_DIR/openclaw.json.bak" ]; then
    echo "[2/4] Restoring config backup..."
    cp "$OPENCLAW_DIR/openclaw.json.bak" "$OPENCLAW_DIR/openclaw.json"
    echo "  Restored openclaw.json from .bak"
else
    echo "[2/4] No config backup found, skipping..."
fi

# 3. Restore from tar backup if specified
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
    if [ -f "$BACKUP_FILE" ]; then
        echo "[3/4] Restoring from backup: $BACKUP_FILE"
        tar -xzf "$BACKUP_FILE" -C /home/openclaw/
        echo "  Restored from tar backup"
    else
        echo "[3/4] Backup file not found: $BACKUP_FILE"
        exit 1
    fi
else
    echo "[3/4] No tar backup specified, using config rollback only"
fi

# 4. Restart containers
echo "[4/4] Restarting containers..."
cd $COMPOSE_DIR && docker compose up -d
sleep 10

# Verify
echo ""
echo "=== Rollback Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""

# Health check
if curl -sf http://127.0.0.1:18789/health > /dev/null 2>&1; then
    echo "OpenClaw: HEALTHY"
else
    echo "OpenClaw: NOT RESPONDING (check logs: docker logs openclaw-agent)"
fi

if curl -sf http://127.0.0.1:18790/health > /dev/null 2>&1; then
    echo "Kommo Webhook: HEALTHY"
else
    echo "Kommo Webhook: NOT RESPONDING"
fi

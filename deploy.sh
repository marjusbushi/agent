#!/bin/bash
# === OpenClaw Deploy Script ===
# Deploys config and code changes to the Hetzner server
set -e

SERVER="root@195.201.218.179"
REMOTE_DIR="/home/openclaw/.openclaw"

echo "=== OpenClaw Deploy ==="

# 1. Sync workspace files
echo "[1/4] Syncing workspace..."
rsync -avz --delete \
  --exclude='node_modules' \
  --exclude='memory/' \
  --exclude='snapshots/' \
  --exclude='*.db' \
  --exclude='*.png' \
  --exclude='*.jpg' \
  workspace/ $SERVER:$REMOTE_DIR/workspace/

rsync -avz --delete \
  --exclude='memory/' \
  --exclude='*.jpg' \
  --exclude='*.png' \
  workspace-melisa/ $SERVER:$REMOTE_DIR/workspace-melisa/

# 2. Sync integrations code (not node_modules or db)
echo "[2/4] Syncing integrations..."
rsync -avz \
  --exclude='node_modules' \
  --exclude='*.db' \
  --exclude='*.db-shm' \
  --exclude='*.db-wal' \
  --exclude='package-lock.json' \
  integrations/ $SERVER:$REMOTE_DIR/integrations/

# 3. Sync Docker files
echo "[3/4] Syncing Docker config..."
rsync -avz docker/docker-compose.yml $SERVER:/home/openclaw/docker-compose.yml
rsync -avz docker/Dockerfile $SERVER:/home/openclaw/Dockerfile

# 4. Restart containers
echo "[4/4] Restarting containers..."
ssh $SERVER "cd /home/openclaw && docker compose down && docker compose up -d --build"

echo ""
echo "=== Deploy complete ==="
ssh $SERVER "docker ps --format 'table {{.Names}}\t{{.Status}}'"

#!/bin/bash
# ============================================
# Kommo CRM Integration Setup
# Instalon dhe konfiguron webhook handler për Kommo
# Ekzekuto në server: bash ~/scripts/05-kommo-integration.sh
# ============================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[GABIM]${NC} $1"; exit 1; }

echo "=========================================="
echo "  Kommo CRM Integration Setup"
echo "=========================================="

# --- Ngarko .env ---
ENV_FILE="$HOME/.openclaw/.env"
if [ ! -f "$ENV_FILE" ]; then
    fail ".env nuk u gjet në $ENV_FILE"
fi
set -a
source "$ENV_FILE"
set +a

# --- Verifiko variablat ---
: "${KOMMO_SUBDOMAIN:?'KOMMO_SUBDOMAIN duhet vendosur në .env'}"
: "${KOMMO_ACCESS_TOKEN:?'KOMMO_ACCESS_TOKEN duhet vendosur në .env'}"
: "${KOMMO_WEBHOOK_SECRET:?'KOMMO_WEBHOOK_SECRET duhet vendosur në .env'}"

echo ""
echo "  Kommo subdomain: $KOMMO_SUBDOMAIN"
echo "  API: https://$KOMMO_SUBDOMAIN.kommo.com/api/v4"

# --- 1. Testo lidhjen me Kommo API ---
echo ""
echo ">>> Testim i lidhjes me Kommo API..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $KOMMO_ACCESS_TOKEN" \
    "https://$KOMMO_SUBDOMAIN.kommo.com/api/v4/account")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
    ACCOUNT_NAME=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','N/A'))" 2>/dev/null || echo "N/A")
    ok "Lidhja me Kommo funksionon (Llogaria: $ACCOUNT_NAME)"
else
    fail "Nuk mund të lidhem me Kommo API (HTTP $HTTP_CODE). Verifiko KOMMO_ACCESS_TOKEN"
fi

# --- 2. Instalo varësitë ---
echo ""
echo ">>> Instalim i varësive..."
if ! command -v node &>/dev/null; then
    fail "Node.js nuk është instaluar. Ekzekuto 01-server-setup.sh së pari"
fi

# Krijo direktorinë e webhook handler
KOMMO_DIR="$HOME/.openclaw/integrations/kommo"
mkdir -p "$KOMMO_DIR"

# Inicializo npm nëse nuk ekziston
if [ ! -f "$KOMMO_DIR/package.json" ]; then
    cd "$KOMMO_DIR"
    npm init -y > /dev/null 2>&1
    npm install express axios > /dev/null 2>&1
    ok "Varësitë u instaluan (express, axios)"
else
    ok "Varësitë ekzistojnë"
fi

# --- 3. Krijo webhook handler ---
echo ""
echo ">>> Krijimi i webhook handler..."
cat > "$KOMMO_DIR/webhook-handler.js" << 'WEBHOOK_EOF'
/**
 * Kommo Webhook Handler for OpenClaw
 * Merr ngjarje nga Kommo dhe i dërgon te OpenClaw gateway
 */
const express = require('express');
const axios = require('axios');
const crypto = require('crypto');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// --- Konfigurimi ---
const CONFIG = {
    port: parseInt(process.env.KOMMO_WEBHOOK_PORT || '18790'),
    mode: process.env.KOMMO_MODE || 'training', // 'training' ose 'live'
    kommo: {
        subdomain: process.env.KOMMO_SUBDOMAIN,
        token: process.env.KOMMO_ACCESS_TOKEN,
        secret: process.env.KOMMO_WEBHOOK_SECRET,
        apiBase: `https://${process.env.KOMMO_SUBDOMAIN}.kommo.com/api/v4`
    },
    openclaw: {
        url: `http://localhost:${process.env.OPENCLAW_PORT || '18789'}`,
        secret: process.env.OPENCLAW_GATEWAY_SECRET
    },
    telegram: {
        token: process.env.TELEGRAM_BOT_TOKEN,
        chatId: process.env.TELEGRAM_ADMIN_CHAT_ID
    }
};

// --- Training Log ---
const fs = require('fs');
const path = require('path');
const TRAINING_LOG_DIR = path.join(process.env.HOME || '/home/openclaw', '.openclaw/training-data');
if (!fs.existsSync(TRAINING_LOG_DIR)) fs.mkdirSync(TRAINING_LOG_DIR, { recursive: true });

function logTrainingData(type, data) {
    const timestamp = new Date().toISOString();
    const logFile = path.join(TRAINING_LOG_DIR, `${new Date().toISOString().split('T')[0]}.jsonl`);
    const entry = JSON.stringify({ timestamp, type, ...data });
    fs.appendFileSync(logFile, entry + '\n');
    console.log(`[Training] ${type}: ${JSON.stringify(data).substring(0, 150)}`);
}

// Pending approvals storage
const pendingReplies = new Map(); // leadId -> { suggestedReply, message, timestamp }

// --- Kommo API Helper ---
const kommoApi = axios.create({
    baseURL: CONFIG.kommo.apiBase,
    headers: {
        'Authorization': `Bearer ${CONFIG.kommo.token}`,
        'Content-Type': 'application/json'
    }
});

// Rate limiting: Kommo lejon 7 requests/sec
let lastRequest = 0;
async function rateLimitedRequest(method, url, data) {
    const now = Date.now();
    const diff = now - lastRequest;
    if (diff < 150) {
        await new Promise(r => setTimeout(r, 150 - diff));
    }
    lastRequest = Date.now();
    return kommoApi({ method, url, data });
}

// --- Telegram njoftim ---
async function notifyTelegram(message) {
    if (!CONFIG.telegram.token || !CONFIG.telegram.chatId) return;
    try {
        await axios.post(
            `https://api.telegram.org/bot${CONFIG.telegram.token}/sendMessage`,
            {
                chat_id: CONFIG.telegram.chatId,
                text: message,
                parse_mode: 'HTML'
            }
        );
    } catch (err) {
        console.error('[Telegram] Gabim:', err.message);
    }
}

// --- Webhook endpoint ---
app.post('/webhooks/kommo', async (req, res) => {
    try {
        const payload = req.body;
        console.log('[Webhook] Ngjarje e re nga Kommo:', JSON.stringify(payload).substring(0, 200));

        // Proceso sipas tipit të ngjarjes
        if (payload.leads) {
            if (payload.leads.add) {
                for (const lead of payload.leads.add) {
                    await handleNewLead(lead);
                }
            }
            if (payload.leads.update) {
                for (const lead of payload.leads.update) {
                    await handleUpdatedLead(lead);
                }
            }
            if (payload.leads.status) {
                for (const lead of payload.leads.status) {
                    await handleStatusChange(lead);
                }
            }
        }

        // Mesazhe të reja (nga chat/Instagram/WhatsApp)
        if (payload.message) {
            if (payload.message.add) {
                for (const msg of payload.message.add) {
                    await handleNewMessage(msg);
                }
            }
        }

        res.status(200).json({ status: 'ok' });
    } catch (err) {
        console.error('[Webhook] Gabim:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// --- Handler: Lead i ri ---
async function handleNewLead(lead) {
    const leadName = lead.name || 'Pa emër';
    const leadId = lead.id;
    const price = lead.price || 0;

    console.log(`[Lead] I ri: #${leadId} - ${leadName}`);

    // Ruaj në training log
    logTrainingData('new_lead', { leadId, leadName, price, raw: lead });

    // Merr kontaktin e lidhur
    let contactInfo = '';
    let contactName = '';
    try {
        const details = await rateLimitedRequest('get', `/leads/${leadId}?with=contacts`);
        const contacts = details.data?._embedded?.contacts || [];
        if (contacts.length > 0) {
            const contact = await rateLimitedRequest('get', `/contacts/${contacts[0].id}`);
            const cData = contact.data;
            contactName = cData.name || '';
            const phone = cData.custom_fields_values?.find(f => f.field_code === 'PHONE')?.values?.[0]?.value || '';
            const email = cData.custom_fields_values?.find(f => f.field_code === 'EMAIL')?.values?.[0]?.value || '';
            contactInfo = `\nKontakti: ${cData.name || 'N/A'}${phone ? '\nTel: ' + phone : ''}${email ? '\nEmail: ' + email : ''}`;
            logTrainingData('lead_contact', { leadId, contactName, phone, email });
        }
    } catch (err) {
        console.error('[Lead] Gabim kontakti:', err.message);
    }

    const modeLabel = CONFIG.mode === 'training' ? '🔬 TRAJNIM' : '🟢 LIVE';

    await notifyTelegram(
        `🆕 <b>Lead i ri në Kommo</b> [${modeLabel}]\n` +
        `ID: #${leadId}\n` +
        `Emri: ${leadName}\n` +
        `Çmimi: €${price}${contactInfo}\n\n` +
        `📋 <b>Komandat:</b>\n` +
        `/lead ${leadId} — Shiko detajet\n` +
        `/lead-reply ${leadId} — Përgjigju\n` +
        `/lead-move ${leadId} — Ndrysho statusin\n\n` +
        `⚠️ <i>Modaliteti trajnim: Melisa vetëm lexon, nuk përgjigjet automatikisht</i>`
    );
}

// --- Handler: Lead i përditësuar ---
async function handleUpdatedLead(lead) {
    console.log(`[Lead] Përditësuar: #${lead.id} - ${lead.name || 'N/A'}`);
}

// --- Handler: Ndryshim statusi ---
async function handleStatusChange(lead) {
    const statusNames = {
        68753235: 'Incoming leads',
        68753239: 'Returned leads',
        68753243: 'Kontaktuar',
        68753247: 'Kliente Dembel',
        68753251: 'Konfirmimi i te dhenave',
        142: 'Closed - won',
        143: 'Closed - lost'
    };

    const oldStatus = lead.old_status_id;
    const newStatus = lead.status_id;

    console.log(`[Lead] Status: #${lead.id} ${statusNames[oldStatus] || oldStatus} → ${statusNames[newStatus] || newStatus}`);

    // Njofto per cdo ndryshim statusi
    await notifyTelegram(
        `📊 <b>Lead status ndryshoi</b>\n` +
        `ID: #${lead.id}\n` +
        `Nga: ${statusNames[oldStatus] || oldStatus}\n` +
        `Në: ${statusNames[newStatus] || newStatus}`
    );
}

// --- Handler: Mesazh i ri ---
async function handleNewMessage(msg) {
    const text = msg.text || '';
    const entityId = msg.entity_id;
    const entityType = msg.entity_type;
    const author = msg.author || {};

    console.log(`[Mesazh] I ri për ${entityType} #${entityId}: ${text.substring(0, 100)}`);

    // Ruaj në training log
    logTrainingData('incoming_message', {
        leadId: entityId,
        entityType,
        text,
        author: author.name || 'N/A',
        isBot: author.is_bot || false
    });

    const modeLabel = CONFIG.mode === 'training' ? '🔬 TRAJNIM' : '🟢 LIVE';

    // Njofto në Telegram me opsion sugjerimi
    await notifyTelegram(
        `💬 <b>Mesazh i ri nga lead</b> [${modeLabel}]\n` +
        `Lead ID: #${entityId}\n` +
        `Nga: ${author.name || 'Klient'}\n` +
        `Mesazhi: ${text.substring(0, 500)}\n\n` +
        `📋 <b>Veprimet:</b>\n` +
        `/lead ${entityId} — Shiko historikun\n` +
        `/lead-reply ${entityId} [mesazhi] — Përgjigju manualisht\n` +
        `/lead-suggest ${entityId} — Melisa sugjeron përgjigje\n\n` +
        `⚠️ <i>Modaliteti trajnim: Asnjë përgjigje automatike. Ti vendos!</i>`
    );

    // Në modalitetin training, logo edhe për analizë
    if (CONFIG.mode === 'training') {
        logTrainingData('training_opportunity', {
            leadId: entityId,
            customerMessage: text,
            timestamp: new Date().toISOString(),
            needsReview: true
        });
    }
}

// --- API Routes për OpenClaw ---

// Listo leads
app.get('/api/leads', async (req, res) => {
    try {
        const page = req.query.page || 1;
        const limit = req.query.limit || 20;
        const status = req.query.status || '';
        const query = req.query.query || '';

        let url = `/leads?page=${page}&limit=${limit}&with=contacts`;
        if (query) url += `&query=${encodeURIComponent(query)}`;

        const response = await rateLimitedRequest('get', url);
        const leads = response.data?._embedded?.leads || [];

        res.json({
            success: true,
            count: leads.length,
            leads: leads.map(l => ({
                id: l.id,
                name: l.name,
                price: l.price,
                status_id: l.status_id,
                pipeline_id: l.pipeline_id,
                created_at: new Date(l.created_at * 1000).toISOString(),
                updated_at: new Date(l.updated_at * 1000).toISOString(),
                contacts: l._embedded?.contacts?.map(c => ({ id: c.id })) || []
            }))
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Merr lead specifik
app.get('/api/leads/:id', async (req, res) => {
    try {
        const response = await rateLimitedRequest('get', `/leads/${req.params.id}?with=contacts,catalog_elements`);
        const lead = response.data;

        // Merr shënimet/mesazhet
        let notes = [];
        try {
            const notesRes = await rateLimitedRequest('get', `/leads/${req.params.id}/notes?limit=20`);
            notes = notesRes.data?._embedded?.notes || [];
        } catch (e) { /* nuk ka shënime */ }

        res.json({
            success: true,
            lead: {
                id: lead.id,
                name: lead.name,
                price: lead.price,
                status_id: lead.status_id,
                pipeline_id: lead.pipeline_id,
                responsible_user_id: lead.responsible_user_id,
                created_at: new Date(lead.created_at * 1000).toISOString(),
                updated_at: new Date(lead.updated_at * 1000).toISOString(),
                custom_fields: lead.custom_fields_values || [],
                contacts: lead._embedded?.contacts || [],
                tags: lead._embedded?.tags || []
            },
            notes: notes.map(n => ({
                id: n.id,
                type: n.note_type,
                text: n.params?.text || n.params?.service || '',
                created_at: new Date(n.created_at * 1000).toISOString(),
                created_by: n.created_by
            }))
        });
    } catch (err) {
        if (err.response?.status === 404) {
            res.status(404).json({ error: `Lead #${req.params.id} nuk u gjet` });
        } else {
            res.status(500).json({ error: err.message });
        }
    }
});

// Përditëso lead (status, emër, çmim)
app.patch('/api/leads/:id', async (req, res) => {
    try {
        const updates = {};
        if (req.body.name) updates.name = req.body.name;
        if (req.body.price !== undefined) updates.price = req.body.price;
        if (req.body.status_id) updates.status_id = req.body.status_id;
        if (req.body.pipeline_id) updates.pipeline_id = req.body.pipeline_id;

        const response = await rateLimitedRequest('patch', `/leads/${req.params.id}`, updates);
        res.json({ success: true, lead: response.data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Fshi lead
app.delete('/api/leads/:id', async (req, res) => {
    try {
        // Kommo nuk ka delete direkt - e mbyllim si "humbur"
        // Ose mund ta bëjmë archive
        await rateLimitedRequest('patch', `/leads/${req.params.id}`, {
            status_id: 143 // "lost" status - duhet përshtatur sipas pipeline
        });
        res.json({ success: true, message: `Lead #${req.params.id} u mbyll si i humbur` });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Shto shënim në lead
app.post('/api/leads/:id/notes', async (req, res) => {
    try {
        const response = await rateLimitedRequest('post', `/leads/${req.params.id}/notes`, [
            {
                note_type: 'common',
                params: { text: req.body.text || req.body.note }
            }
        ]);
        res.json({ success: true, note: response.data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Merr pipelines dhe statuset
app.get('/api/pipelines', async (req, res) => {
    try {
        const response = await rateLimitedRequest('get', '/leads/pipelines');
        const pipelines = response.data?._embedded?.pipelines || [];
        res.json({
            success: true,
            pipelines: pipelines.map(p => ({
                id: p.id,
                name: p.name,
                statuses: p._embedded?.statuses?.map(s => ({
                    id: s.id,
                    name: s.name,
                    color: s.color,
                    type: s.type
                })) || []
            }))
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Training data - shiko te dhenat e mbledhura
app.get('/api/training', async (req, res) => {
    try {
        const files = fs.readdirSync(TRAINING_LOG_DIR).filter(f => f.endsWith('.jsonl')).sort().reverse();
        const date = req.query.date || (files[0] ? files[0].replace('.jsonl','') : '');
        const filePath = path.join(TRAINING_LOG_DIR, `${date}.jsonl`);

        if (!fs.existsSync(filePath)) {
            return res.json({ success: true, entries: [], dates: files.map(f => f.replace('.jsonl','')) });
        }

        const entries = fs.readFileSync(filePath, 'utf8')
            .split('\n')
            .filter(line => line.trim())
            .map(line => JSON.parse(line));

        res.json({
            success: true,
            date,
            count: entries.length,
            entries,
            dates: files.map(f => f.replace('.jsonl',''))
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Training stats - statistikat e trajnimit
app.get('/api/training/stats', async (req, res) => {
    try {
        const files = fs.readdirSync(TRAINING_LOG_DIR).filter(f => f.endsWith('.jsonl'));
        let totalEntries = 0;
        let types = {};

        for (const file of files) {
            const lines = fs.readFileSync(path.join(TRAINING_LOG_DIR, file), 'utf8')
                .split('\n').filter(l => l.trim());
            totalEntries += lines.length;
            for (const line of lines) {
                try {
                    const entry = JSON.parse(line);
                    types[entry.type] = (types[entry.type] || 0) + 1;
                } catch(e) {}
            }
        }

        res.json({
            success: true,
            mode: CONFIG.mode,
            totalDays: files.length,
            totalEntries,
            byType: types,
            logDir: TRAINING_LOG_DIR
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Ndrysho mode (training ↔ live)
app.post('/api/mode', (req, res) => {
    const newMode = req.body.mode;
    if (!['training', 'live'].includes(newMode)) {
        return res.status(400).json({ error: "Mode duhet te jete 'training' ose 'live'" });
    }
    const oldMode = CONFIG.mode;
    CONFIG.mode = newMode;
    logTrainingData('mode_change', { from: oldMode, to: newMode });
    res.json({ success: true, mode: CONFIG.mode, message: `Modaliteti u ndryshua ne: ${newMode}` });
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'kommo-webhook',
        mode: CONFIG.mode,
        uptime: process.uptime()
    });
});

// --- Fillo serverin ---
const PORT = CONFIG.port;
app.listen(PORT, () => {
    console.log(`[Kommo Webhook] Duke dëgjuar në port ${PORT}`);
    console.log(`[Kommo Webhook] Webhook URL: https://YOUR_DOMAIN:${PORT}/webhooks/kommo`);
    console.log(`[Kommo Webhook] API URL: http://localhost:${PORT}/api/`);
});
WEBHOOK_EOF

ok "Webhook handler u krijua"

# --- 4. Krijo systemd service ---
echo ""
echo ">>> Krijimi i systemd service..."
sudo tee /etc/systemd/system/kommo-webhook.service > /dev/null << SYSTEMD_EOF
[Unit]
Description=Kommo Webhook Handler for OpenClaw
After=network.target openclaw.service

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$KOMMO_DIR
EnvironmentFile=$HOME/.openclaw/.env
ExecStart=$(which node) webhook-handler.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

sudo systemctl daemon-reload
sudo systemctl enable kommo-webhook
ok "Systemd service u krijua"

# --- 5. Krijo kommo-cli.sh (helper) ---
echo ""
echo ">>> Krijimi i CLI helper..."
cat > "$KOMMO_DIR/kommo-cli.sh" << 'CLI_EOF'
#!/bin/bash
# Kommo CLI Helper — Përdor direkt ose nëpërmjet OpenClaw
# Përdorim: bash kommo-cli.sh [komandë] [argumente]
set -euo pipefail

API_URL="http://localhost:${KOMMO_WEBHOOK_PORT:-18790}/api"

case "${1:-help}" in
    leads|list)
        echo "📋 Leads aktive:"
        curl -s "$API_URL/leads?limit=${2:-10}" | python3 -m json.tool
        ;;
    lead|show)
        [ -z "${2:-}" ] && { echo "Përdorim: kommo-cli.sh lead <ID>"; exit 1; }
        echo "📄 Lead #$2:"
        curl -s "$API_URL/leads/$2" | python3 -m json.tool
        ;;
    close)
        [ -z "${2:-}" ] && { echo "Përdorim: kommo-cli.sh close <ID>"; exit 1; }
        echo "❌ Duke mbyllur lead #$2..."
        curl -s -X PATCH "$API_URL/leads/$2" -H 'Content-Type: application/json' \
            -d "{\"status_id\": 143}" | python3 -m json.tool
        ;;
    move)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "Përdorim: kommo-cli.sh move <ID> <STATUS_ID>"; exit 1; }
        echo "➡️ Duke lëvizur lead #$2 në status $3..."
        curl -s -X PATCH "$API_URL/leads/$2" -H 'Content-Type: application/json' \
            -d "{\"status_id\": $3}" | python3 -m json.tool
        ;;
    note)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "Përdorim: kommo-cli.sh note <ID> <teksti>"; exit 1; }
        echo "📝 Duke shtuar shënim..."
        curl -s -X POST "$API_URL/leads/$2/notes" -H 'Content-Type: application/json' \
            -d "{\"text\": \"${*:3}\"}" | python3 -m json.tool
        ;;
    delete|fshi)
        [ -z "${2:-}" ] && { echo "Përdorim: kommo-cli.sh delete <ID>"; exit 1; }
        echo "🗑️ Duke fshirë (mbyllur) lead #$2..."
        curl -s -X DELETE "$API_URL/leads/$2" | python3 -m json.tool
        ;;
    pipelines)
        echo "🔄 Pipelines:"
        curl -s "$API_URL/pipelines" | python3 -m json.tool
        ;;
    help|*)
        echo "============================================"
        echo "  Kommo CLI Helper"
        echo "============================================"
        echo ""
        echo "  Komandat:"
        echo "    leads [limit]          — Shfaq leads (default: 10)"
        echo "    lead <ID>              — Shfaq detajet e lead-it"
        echo "    close <ID>             — Mbyll lead si 'i humbur'"
        echo "    move <ID> <STATUS_ID>  — Lëviz lead në status tjetër"
        echo "    note <ID> <tekst>      — Shto shënim"
        echo "    delete <ID>            — Fshi (mbyll) lead"
        echo "    pipelines              — Shfaq pipelines dhe statuset"
        echo ""
        ;;
esac
CLI_EOF
chmod +x "$KOMMO_DIR/kommo-cli.sh"
ok "CLI helper u krijua"

# --- 6. Konfiguro firewall ---
echo ""
echo ">>> Kontrolli i firewall..."
WEBHOOK_PORT="${KOMMO_WEBHOOK_PORT:-18790}"
if command -v ufw &>/dev/null; then
    sudo ufw allow "$WEBHOOK_PORT/tcp" comment "Kommo webhook" 2>/dev/null || true
    ok "Porta $WEBHOOK_PORT u hap në UFW"
elif command -v firewall-cmd &>/dev/null; then
    sudo firewall-cmd --add-port="$WEBHOOK_PORT/tcp" --permanent 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
    ok "Porta $WEBHOOK_PORT u hap"
else
    warn "Nuk u gjet firewall. Sigurohu që porta $WEBHOOK_PORT është e hapur"
fi

# --- 7. Fillo shërbimin ---
echo ""
echo ">>> Fillimi i shërbimit..."
sudo systemctl start kommo-webhook
sleep 2

if systemctl is-active --quiet kommo-webhook; then
    ok "Kommo webhook handler po funksionon"
else
    warn "Shërbimi nuk u fillua. Kontrollo me: journalctl -u kommo-webhook -f"
fi

echo ""
echo "=========================================="
echo "  KOMMO INTEGRATION - E PËRFUNDUAR"
echo "=========================================="
echo ""
echo "  Shërbimi: kommo-webhook (port $WEBHOOK_PORT)"
echo "  Webhook URL: https://YOUR_DOMAIN:$WEBHOOK_PORT/webhooks/kommo"
echo "  CLI: bash $KOMMO_DIR/kommo-cli.sh help"
echo ""
echo "  ⚡ HAPI TJETËR:"
echo "  1. Shko te Kommo → Settings → Integrations → Webhooks"
echo "  2. Shto webhook URL: https://YOUR_DOMAIN:$WEBHOOK_PORT/webhooks/kommo"
echo "  3. Zgjidh ngjarjet: leads (add/update/status), messages"
echo ""
echo "  Kontrollo statusin:"
echo "    systemctl status kommo-webhook"
echo "    journalctl -u kommo-webhook -f"
echo "    curl http://localhost:$WEBHOOK_PORT/health"
echo "=========================================="

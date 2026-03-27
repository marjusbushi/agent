#!/bin/bash
# ============================================
# Price Expert Agent Setup
# Standalone bot: Express + Anthropic SDK + Telegram
# Ekzekuto në server: bash ~/scripts/06-price-expert-setup.sh
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
echo "  Price Expert Agent Setup"
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
: "${TELEGRAM_PE_BOT_TOKEN:?'TELEGRAM_PE_BOT_TOKEN duhet vendosur në .env'}"
: "${TELEGRAM_PE_ADMIN_CHAT_ID:?'TELEGRAM_PE_ADMIN_CHAT_ID duhet vendosur në .env'}"
: "${ANTHROPIC_API_KEY:?'ANTHROPIC_API_KEY duhet vendosur në .env'}"
: "${DIS_API_BASE_URL:?'DIS_API_BASE_URL duhet vendosur në .env'}"
: "${DIS_API_TOKEN:?'DIS_API_TOKEN duhet vendosur në .env'}"

PE_PORT="${PE_OPENCLAW_PORT:-18791}"

echo ""
echo "  Telegram Bot: ${TELEGRAM_PE_BOT_TOKEN:0:10}..."
echo "  DIS API: $DIS_API_BASE_URL"
echo "  Port: $PE_PORT"

# --- 1. Verifiko Node.js ---
echo ""
echo ">>> Verifikim i Node.js..."
if ! command -v node &>/dev/null; then
    fail "Node.js nuk është instaluar. Ekzekuto 02-install-openclaw.sh së pari"
fi
ok "Node.js $(node -v)"

# --- 2. Krijo direktorinë ---
PE_DIR="$HOME/.openclaw/integrations/price-expert"
mkdir -p "$PE_DIR"
mkdir -p "$HOME/.openclaw/logs"

# --- 3. Inicializo npm + instalo varësitë ---
echo ""
echo ">>> Instalim i varësive..."
cd "$PE_DIR"
if [ ! -f "package.json" ]; then
    npm init -y > /dev/null 2>&1
fi
npm install node-telegram-bot-api@0 @anthropic-ai/sdk@0 axios@1 express@4 > /dev/null 2>&1
ok "Varësitë u instaluan"

# --- 4. Kopjo IDENTITY.md ---
echo ""
echo ">>> Kopjim i IDENTITY.md..."
if [ -f "$HOME/.openclaw/workspace/price-expert/IDENTITY.md" ]; then
    cp "$HOME/.openclaw/workspace/price-expert/IDENTITY.md" "$PE_DIR/IDENTITY.md"
    ok "IDENTITY.md u kopjua"
else
    warn "IDENTITY.md nuk u gjet — do përdoret identity default"
fi

# --- 5. Krijo bot-in ---
echo ""
echo ">>> Krijimi i Price Expert bot..."
cat > "$PE_DIR/price-expert-bot.js" << 'BOT_EOF'
/**
 * Price Expert Bot — Standalone
 * Express + Anthropic SDK + node-telegram-bot-api
 * Menaxhon pricelists në DIS via API Bot/V1
 */
const express = require('express');
const TelegramBot = require('node-telegram-bot-api');
const Anthropic = require('@anthropic-ai/sdk').default;
const axios = require('axios');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ── Config ───────────────────────────────────────────────────
const CONFIG = {
    port: parseInt(process.env.PE_OPENCLAW_PORT || '18791'),
    telegram: {
        token: process.env.TELEGRAM_PE_BOT_TOKEN,
        adminChatId: process.env.TELEGRAM_PE_ADMIN_CHAT_ID,
    },
    anthropic: {
        apiKey: process.env.ANTHROPIC_API_KEY,
        model: 'claude-sonnet-4-6',
        maxTokens: 4096,
        temperature: 0.3,
    },
    dis: {
        baseUrl: process.env.DIS_API_BASE_URL,
        token: process.env.DIS_API_TOKEN,
        timeout: 10000,
        maxRetries: 3,
        retryDelays: [1000, 2000, 4000], // exponential backoff
    },
};

// ── Logging ──────────────────────────────────────────────────
const LOG_DIR = path.join(process.env.HOME || '/home/openclaw', '.openclaw/logs');
if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

function log(type, data) {
    const entry = JSON.stringify({
        timestamp: new Date().toISOString(),
        type,
        ...data,
    });
    const file = path.join(LOG_DIR, `price-expert-${new Date().toISOString().split('T')[0]}.jsonl`);
    fs.appendFileSync(file, entry + '\n');
}

// ── DIS API Client ───────────────────────────────────────────
const disApi = axios.create({
    baseURL: CONFIG.dis.baseUrl,
    timeout: CONFIG.dis.timeout,
    headers: {
        'Authorization': `Bearer ${CONFIG.dis.token}`,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    },
});

// Rate limiter queue
let lastDisCall = 0;
async function rateLimitedDisCall(method, url, data = null, params = null) {
    const now = Date.now();
    const diff = now - lastDisCall;
    if (diff < 200) await new Promise(r => setTimeout(r, 200 - diff));
    lastDisCall = Date.now();

    const requestId = crypto.randomUUID();
    const start = Date.now();

    for (let attempt = 0; attempt < CONFIG.dis.maxRetries; attempt++) {
        try {
            const response = await disApi({ method, url, data, params });
            log('dis_api', {
                request_id: requestId,
                method, url, status: response.status,
                response_time_ms: Date.now() - start,
                attempt: attempt + 1,
            });
            return response.data;
        } catch (err) {
            const status = err.response?.status;
            if (status === 401 || status === 403) {
                throw new Error('Token-i i DIS ka problem — kontakto admin.');
            }
            if (status === 404) {
                throw new Error(err.response?.data?.message || 'Nuk u gjet.');
            }
            if (status === 422) {
                const errors = err.response?.data?.errors || {};
                throw new Error('Validation: ' + Object.values(errors).flat().join(', '));
            }
            if (status === 429) {
                if (attempt < CONFIG.dis.maxRetries - 1) {
                    await new Promise(r => setTimeout(r, CONFIG.dis.retryDelays[attempt]));
                    continue;
                }
                throw new Error('DIS ka shume requests — provo pas 30 sekondash.');
            }
            if (attempt < CONFIG.dis.maxRetries - 1) {
                await new Promise(r => setTimeout(r, CONFIG.dis.retryDelays[attempt]));
                continue;
            }
            log('dis_error', { request_id: requestId, method, url, error: err.message, attempt: attempt + 1 });
            throw new Error('DIS nuk pergjigjet — provo pas pak.');
        }
    }
}

// ── Strip costs for privacy ──────────────────────────────────
function stripCosts(obj) {
    if (typeof obj !== 'object' || obj === null) return obj;
    if (Array.isArray(obj)) return obj.map(stripCosts);
    const clean = {};
    for (const [key, value] of Object.entries(obj)) {
        if (['purchase_rate', 'cost', 'margin_amount'].includes(key)) continue;
        clean[key] = stripCosts(value);
    }
    return clean;
}

// ── Claude Tools (DIS API) ───────────────────────────────────
const TOOLS = [
    {
        name: 'list_pricelists',
        description: 'Listo te gjitha pricelists. Params: active (bool), name (string), per_page (max 50).',
        input_schema: {
            type: 'object',
            properties: {
                active: { type: 'boolean', description: 'Filtro vetem aktive ose jo-aktive' },
                name: { type: 'string', description: 'Kerko me emer' },
                page: { type: 'number' },
                per_page: { type: 'number' },
            },
        },
    },
    {
        name: 'active_pricelists',
        description: 'Merr vetem pricelists aktive (active=true ose brenda date range).',
        input_schema: { type: 'object', properties: {} },
    },
    {
        name: 'show_pricelist',
        description: 'Detajet e nje pricelist. Tregon item count, data fillimit/mbarimit, status.',
        input_schema: {
            type: 'object',
            properties: { serial: { type: 'string', description: 'Serial i pricelist (PRL-XXXXXXX)' } },
            required: ['serial'],
        },
    },
    {
        name: 'list_pricelist_items',
        description: 'Artikujt brenda nje pricelist me cmime origjinale dhe te zbritura.',
        input_schema: {
            type: 'object',
            properties: {
                serial: { type: 'string' },
                category: { type: 'string' },
                name: { type: 'string' },
                min_price: { type: 'number' },
                max_price: { type: 'number' },
                page: { type: 'number' },
                per_page: { type: 'number' },
            },
            required: ['serial'],
        },
    },
    {
        name: 'markdown_analysis',
        description: 'Analiza e grupeve: sell-through %, weeks of cover, urgency, suggested discount. Filtra: category, style, season, year, urgency (low/medium/high), sort, dir.',
        input_schema: {
            type: 'object',
            properties: {
                date_from: { type: 'string' },
                date_to: { type: 'string' },
                category: { type: 'string' },
                style: { type: 'string' },
                season: { type: 'string' },
                year: { type: 'string' },
                urgency: { type: 'string', enum: ['low', 'medium', 'high'] },
                sort: { type: 'string' },
                dir: { type: 'string', enum: ['asc', 'desc'] },
                per_page: { type: 'number' },
            },
        },
    },
    {
        name: 'item_analysis',
        description: 'Analiza e detajuar e nje artikulli: stok, shitje, marzh, trend, lifecycle, pricelists aktive.',
        input_schema: {
            type: 'object',
            properties: { item_id: { type: 'number', description: 'ID e artikullit' } },
            required: ['item_id'],
        },
    },
    {
        name: 'group_analysis',
        description: 'Analiza e grupit (te gjitha variantet e nje produkti): stok, shitje, trend, seasonal, pricing.',
        input_schema: {
            type: 'object',
            properties: { group_code: { type: 'string', description: 'Kodi i grupit (item_group code)' } },
            required: ['group_code'],
        },
    },
    {
        name: 'get_filters',
        description: 'Merr listat e kategorive, sezoneve, viteve, stileve, vendor-ave. Perdor kur useri nuk di opsionet.',
        input_schema: { type: 'object', properties: {} },
    },
    {
        name: 'preview_bulk',
        description: 'Dry run — numeron sa artikuj preken nga filtrat e dhena pa i shtuar. Perdor PARA bulk_add per konfirmim.',
        input_schema: {
            type: 'object',
            properties: {
                discount_type: { type: 'string', enum: ['percentage', 'fixed', 'deduction'] },
                discount_value: { type: 'number' },
                rounding: { type: 'boolean' },
                categories: { type: 'array', items: { type: 'string' } },
                groups: { type: 'array', items: { type: 'string' } },
                years: { type: 'array', items: { type: 'string' } },
                seasons: { type: 'array', items: { type: 'string' } },
                styles: { type: 'array', items: { type: 'string' } },
                vendors: { type: 'array', items: { type: 'string' } },
                name_search: { type: 'string' },
                min_rate: { type: 'number' },
                max_rate: { type: 'number' },
            },
            required: ['discount_type', 'discount_value'],
        },
    },
    {
        name: 'compare_pricelists',
        description: 'Krahaso dy pricelists: artikuj vetem ne njeren, artikuj te perbashket me ndryshim cmimi.',
        input_schema: {
            type: 'object',
            properties: {
                serial1: { type: 'string' },
                serial2: { type: 'string' },
            },
            required: ['serial1', 'serial2'],
        },
    },
    {
        name: 'create_pricelist',
        description: 'Krijo pricelist te re. KERKON konfirmim nga admin para thirrjes.',
        input_schema: {
            type: 'object',
            properties: {
                name: { type: 'string' },
                starts_at: { type: 'string', description: 'YYYY-MM-DD' },
                ends_at: { type: 'string', description: 'YYYY-MM-DD' },
                active: { type: 'boolean' },
                enable_on_pos: { type: 'boolean' },
                enable_on_web: { type: 'boolean' },
                notes: { type: 'string' },
            },
            required: ['name'],
        },
    },
    {
        name: 'update_pricelist',
        description: 'Perditeso metadata te pricelist: emer, data, active, POS/Web, shenime. KERKON konfirmim.',
        input_schema: {
            type: 'object',
            properties: {
                serial: { type: 'string' },
                name: { type: 'string' },
                starts_at: { type: 'string' },
                ends_at: { type: 'string' },
                active: { type: 'boolean' },
                enable_on_pos: { type: 'boolean' },
                enable_on_web: { type: 'boolean' },
                notes: { type: 'string' },
            },
            required: ['serial'],
        },
    },
    {
        name: 'delete_pricelist',
        description: 'Fshi nje pricelist. KERKON konfirmim.',
        input_schema: {
            type: 'object',
            properties: { serial: { type: 'string' } },
            required: ['serial'],
        },
    },
    {
        name: 'bulk_add_items',
        description: 'Shto artikuj ne pricelist me zbritje bazuar ne filtra. KERKON konfirmim. Perdor preview_bulk me pare.',
        input_schema: {
            type: 'object',
            properties: {
                serial: { type: 'string' },
                discount_type: { type: 'string', enum: ['percentage', 'fixed', 'deduction'] },
                discount_value: { type: 'number' },
                rounding: { type: 'boolean' },
                categories: { type: 'array', items: { type: 'string' } },
                groups: { type: 'array', items: { type: 'string' } },
                years: { type: 'array', items: { type: 'string' } },
                seasons: { type: 'array', items: { type: 'string' } },
                styles: { type: 'array', items: { type: 'string' } },
                vendors: { type: 'array', items: { type: 'string' } },
                name_search: { type: 'string' },
                min_rate: { type: 'number' },
                max_rate: { type: 'number' },
            },
            required: ['serial', 'discount_type', 'discount_value'],
        },
    },
    {
        name: 'bulk_update_prices',
        description: 'Ndrysho cmime direkt per artikuj specifikë. KERKON konfirmim.',
        input_schema: {
            type: 'object',
            properties: {
                serial: { type: 'string' },
                items: {
                    type: 'array',
                    items: {
                        type: 'object',
                        properties: {
                            item_id: { type: 'number' },
                            discounted_price: { type: 'number' },
                        },
                        required: ['item_id', 'discounted_price'],
                    },
                },
            },
            required: ['serial', 'items'],
        },
    },
    {
        name: 'remove_item',
        description: 'Hiq nje artikull nga pricelist. KERKON konfirmim.',
        input_schema: {
            type: 'object',
            properties: {
                serial: { type: 'string' },
                item_id: { type: 'number' },
            },
            required: ['serial', 'item_id'],
        },
    },
    {
        name: 'sync_web',
        description: 'Sinkronizo pricelist me website. KERKON konfirmim. Vetem per pricelists aktive.',
        input_schema: {
            type: 'object',
            properties: { serial: { type: 'string' } },
            required: ['serial'],
        },
    },
];

// ── Tool Execution ───────────────────────────────────────────
async function executeTool(name, input) {
    switch (name) {
        case 'list_pricelists':
            return stripCosts(await rateLimitedDisCall('get', '/pricelists', null, input));
        case 'active_pricelists':
            return stripCosts(await rateLimitedDisCall('get', '/pricelists/active'));
        case 'show_pricelist':
            return stripCosts(await rateLimitedDisCall('get', `/pricelists/${input.serial}`));
        case 'list_pricelist_items':
            const { serial: itemsSerial, ...itemsParams } = input;
            return stripCosts(await rateLimitedDisCall('get', `/pricelists/${itemsSerial}/items`, null, itemsParams));
        case 'markdown_analysis':
            return stripCosts(await rateLimitedDisCall('get', '/items/markdown-analysis', null, input));
        case 'item_analysis':
            return stripCosts(await rateLimitedDisCall('get', `/items/${input.item_id}/analysis`));
        case 'group_analysis':
            return stripCosts(await rateLimitedDisCall('get', `/items/group/${input.group_code}/analysis`));
        case 'get_filters':
            return await rateLimitedDisCall('get', '/items/filters');
        case 'preview_bulk':
            return stripCosts(await rateLimitedDisCall('post', '/pricelists/preview-bulk', input));
        case 'compare_pricelists':
            return stripCosts(await rateLimitedDisCall('get', '/pricelists/compare', null, { serial1: input.serial1, serial2: input.serial2 }));
        case 'create_pricelist':
            return await rateLimitedDisCall('post', '/pricelists', input);
        case 'update_pricelist':
            const { serial: upSerial, ...upData } = input;
            return await rateLimitedDisCall('patch', `/pricelists/${upSerial}`, upData);
        case 'delete_pricelist':
            return await rateLimitedDisCall('delete', `/pricelists/${input.serial}`);
        case 'bulk_add_items':
            const { serial: addSerial, ...addData } = input;
            return await rateLimitedDisCall('post', `/pricelists/${addSerial}/items/bulk-add`, addData);
        case 'bulk_update_prices':
            const { serial: priceSerial, ...priceData } = input;
            return await rateLimitedDisCall('patch', `/pricelists/${priceSerial}/items/bulk-price`, priceData);
        case 'remove_item':
            return await rateLimitedDisCall('delete', `/pricelists/${input.serial}/items/${input.item_id}`);
        case 'sync_web':
            return await rateLimitedDisCall('post', `/pricelists/${input.serial}/sync-web`);
        default:
            throw new Error(`Tool i panjohur: ${name}`);
    }
}

// ── Conversation Memory ──────────────────────────────────────
const conversations = new Map();
const CONV_MAX_MESSAGES = 20;
const CONV_TTL_MS = 60 * 60 * 1000; // 1 ore

function getConversation(chatId) {
    const conv = conversations.get(chatId);
    if (conv && Date.now() - conv.lastActivity < CONV_TTL_MS) {
        conv.lastActivity = Date.now();
        return conv.messages;
    }
    const messages = [];
    conversations.set(chatId, { messages, lastActivity: Date.now() });
    return messages;
}

function addMessage(chatId, role, content) {
    const messages = getConversation(chatId);
    messages.push({ role, content });
    if (messages.length > CONV_MAX_MESSAGES) {
        messages.splice(0, messages.length - CONV_MAX_MESSAGES);
    }
}

// Pastro konversata te vjetra cdo 10 min
setInterval(() => {
    const now = Date.now();
    for (const [chatId, conv] of conversations) {
        if (now - conv.lastActivity > CONV_TTL_MS) conversations.delete(chatId);
    }
}, 10 * 60 * 1000);

// ── Load System Prompt ───────────────────────────────────────
let systemPrompt = 'Ti je Price Expert — ekspert cmimesh per Zero Absolute. Pergjigju ne shqip.';
const identityPath = path.join(__dirname, 'IDENTITY.md');
if (fs.existsSync(identityPath)) {
    systemPrompt = fs.readFileSync(identityPath, 'utf8');
    console.log('[PE] IDENTITY.md u ngarkua');
}

// ── Anthropic Client ─────────────────────────────────────────
const anthropic = new Anthropic({ apiKey: CONFIG.anthropic.apiKey });

async function chat(chatId, userMessage) {
    addMessage(chatId, 'user', userMessage);
    const messages = getConversation(chatId);

    let response = await anthropic.messages.create({
        model: CONFIG.anthropic.model,
        max_tokens: CONFIG.anthropic.maxTokens,
        temperature: CONFIG.anthropic.temperature,
        system: systemPrompt,
        messages,
        tools: TOOLS,
    });

    // Tool use loop
    while (response.stop_reason === 'tool_use') {
        const toolBlocks = response.content.filter(b => b.type === 'tool_use');
        const toolResults = [];

        for (const toolBlock of toolBlocks) {
            log('tool_call', { tool: toolBlock.name, input: toolBlock.input });
            try {
                const result = await executeTool(toolBlock.name, toolBlock.input);
                toolResults.push({
                    type: 'tool_result',
                    tool_use_id: toolBlock.id,
                    content: JSON.stringify(result),
                });
            } catch (err) {
                toolResults.push({
                    type: 'tool_result',
                    tool_use_id: toolBlock.id,
                    content: JSON.stringify({ error: err.message }),
                    is_error: true,
                });
            }
        }

        // Add assistant message + tool results
        messages.push({ role: 'assistant', content: response.content });
        messages.push({ role: 'user', content: toolResults });

        response = await anthropic.messages.create({
            model: CONFIG.anthropic.model,
            max_tokens: CONFIG.anthropic.maxTokens,
            temperature: CONFIG.anthropic.temperature,
            system: systemPrompt,
            messages,
            tools: TOOLS,
        });
    }

    // Extract text response
    const textBlocks = response.content.filter(b => b.type === 'text');
    const reply = textBlocks.map(b => b.text).join('\n');

    addMessage(chatId, 'assistant', reply);
    log('chat', { chat_id: chatId, user: userMessage.substring(0, 100), reply_length: reply.length });

    return reply;
}

// ── Telegram Bot ─────────────────────────────────────────────
const bot = new TelegramBot(CONFIG.telegram.token, { polling: true });

// Auth: vetem admin
function isAdmin(chatId) {
    return String(chatId) === String(CONFIG.telegram.adminChatId);
}

// Chunk messages for Telegram (max 4000 chars)
function chunkMessage(text, maxLen = 4000) {
    if (text.length <= maxLen) return [text];
    const chunks = [];
    let remaining = text;
    while (remaining.length > 0) {
        if (remaining.length <= maxLen) {
            chunks.push(remaining);
            break;
        }
        let splitAt = remaining.lastIndexOf('\n', maxLen);
        if (splitAt < maxLen * 0.5) splitAt = maxLen;
        chunks.push(remaining.substring(0, splitAt));
        remaining = remaining.substring(splitAt).trimStart();
    }
    return chunks;
}

bot.on('message', async (msg) => {
    const chatId = msg.chat.id;
    const text = msg.text;

    if (!text || !isAdmin(chatId)) return;

    // /start dhe /help
    if (text === '/start' || text === '/help') {
        await bot.sendMessage(chatId,
            `*Price Expert* — Ekspert cmimesh per Zero Absolute\n\n` +
            `*READ:*\n` +
            `/pricelists — Listo pricelists\n` +
            `/active — Pricelists aktive\n` +
            `/analyze — Analiza markdown\n` +
            `/filters — Kategorite/sezonet\n\n` +
            `*Ose shkruaj ne shqip:*\n` +
            `"analizo produktet qe nuk shiten"\n` +
            `"krahaso PRL-001 me PRL-002"\n` +
            `"krijo pricelist verore me -30% per T-shirts"`,
            { parse_mode: 'Markdown' }
        );
        return;
    }

    try {
        await bot.sendChatAction(chatId, 'typing');
        const reply = await chat(chatId, text);
        const chunks = chunkMessage(reply);
        for (const chunk of chunks) {
            await bot.sendMessage(chatId, chunk, { parse_mode: 'Markdown' }).catch(() =>
                bot.sendMessage(chatId, chunk) // retry pa markdown nese deshton
            );
        }
    } catch (err) {
        console.error('[PE] Gabim:', err.message);
        log('error', { chat_id: chatId, error: err.message });

        let errorMsg = 'Ndodhi nje gabim. Provo perseri.';
        if (err.status === 429) errorMsg = 'Jam pak i ngarkuar — provo pas 30 sekondash.';
        if (err.message?.includes('token')) errorMsg = err.message;

        await bot.sendMessage(chatId, errorMsg);
    }
});

console.log('[PE] Price Expert bot filloi');

// ── Health Check Server ──────────────────────────────────────
const app = express();

app.get('/health', async (req, res) => {
    let disStatus = 'unknown';
    try {
        await disApi.get('/pricelists?per_page=1');
        disStatus = 'connected';
    } catch (err) {
        disStatus = err.response?.status === 401 ? 'auth_error' : 'unreachable';
    }

    res.json({
        status: disStatus === 'connected' ? 'ok' : 'degraded',
        service: 'price-expert',
        dis_api: disStatus,
        uptime: process.uptime(),
        conversations: conversations.size,
    });
});

app.listen(CONFIG.port, '127.0.0.1', () => {
    console.log(`[PE] Health check ne port ${CONFIG.port}`);
});
BOT_EOF

ok "Price Expert bot u krijua"

# --- 6. Krijo systemd service ---
echo ""
echo ">>> Krijimi i systemd service..."
sudo tee /etc/systemd/system/price-expert.service > /dev/null << SVCEOF
[Unit]
Description=Price Expert AI Agent
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$PE_DIR
EnvironmentFile=$HOME/.openclaw/.env
ExecStart=$(which node) price-expert-bot.js
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=60

# Siguri
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable price-expert
ok "Systemd service u krijua"

# --- 7. Health check cron ---
echo ""
echo ">>> Vendosja e health check + log rotation cron..."
CRON_LINES="# Price Expert health check (cdo 5 min)
*/5 * * * * curl -sf http://127.0.0.1:$PE_PORT/health > /dev/null || curl -s \"https://api.telegram.org/bot${TELEGRAM_PE_BOT_TOKEN}/sendMessage\" -d \"chat_id=${TELEGRAM_PE_ADMIN_CHAT_ID}&text=⚠️ Price Expert nuk pergjigjet!\" > /dev/null 2>&1
# Price Expert log rotation (cdo dite ne 03:00)
0 3 * * * find $HOME/.openclaw/logs/ -name \"price-expert-*.jsonl\" -mtime +14 -delete"

(crontab -l 2>/dev/null | grep -v 'price-expert'; echo "$CRON_LINES") | crontab -
ok "Cron jobs u vendosen"

# --- 8. Fillo shërbimin ---
echo ""
echo ">>> Fillimi i shërbimit..."
sudo systemctl start price-expert
sleep 2

if systemctl is-active --quiet price-expert; then
    ok "Price Expert po funksionon"
else
    warn "Shërbimi nuk u fillua. Kontrollo: journalctl -u price-expert -f"
fi

echo ""
echo "=========================================="
echo "  PRICE EXPERT — I GATSHËM"
echo "=========================================="
echo ""
echo "  Service: price-expert (port $PE_PORT)"
echo "  Health: curl http://127.0.0.1:$PE_PORT/health"
echo "  Logs: journalctl -u price-expert -f"
echo ""
echo "  Komandat:"
echo "    sudo systemctl start price-expert"
echo "    sudo systemctl stop price-expert"
echo "    sudo systemctl restart price-expert"
echo "    sudo systemctl status price-expert"
echo "=========================================="

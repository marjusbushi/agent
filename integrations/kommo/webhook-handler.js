/**
 * Kommo Webhook Handler v2 — E integruar me Melisa
 * Merr ngjarje nga Kommo, logon, dhe njofton Melisa-n
 */
const express = require("express");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const db = require("./db");
const kommoApi = require("./kommo-api");
const { initBot, notifyNewMessage, notifyNewLead } = require("./melisa-bot");

const app = express();

// --- Rate Limiting (in-memory, per IP) ---
const rateLimiter = new Map();
const RATE_LIMIT = { windowMs: 60000, maxRequests: 60 };

function checkRateLimit(ip) {
    const now = Date.now();
    const record = rateLimiter.get(ip) || { count: 0, resetAt: now + RATE_LIMIT.windowMs };
    if (now > record.resetAt) {
        record.count = 0;
        record.resetAt = now + RATE_LIMIT.windowMs;
    }
    record.count++;
    rateLimiter.set(ip, record);
    return record.count <= RATE_LIMIT.maxRequests;
}

// Cleanup old entries every 5 minutes
setInterval(() => {
    const now = Date.now();
    for (const [ip, record] of rateLimiter) {
        if (now > record.resetAt + RATE_LIMIT.windowMs) rateLimiter.delete(ip);
    }
}, 300000);

app.use((req, res, next) => {
    const ip = req.headers["x-real-ip"] || req.ip;
    if (!checkRateLimit(ip)) {
        console.log(`[RateLimit] Blocked: ${ip}`);
        return res.status(429).json({ error: "Too many requests" });
    }
    next();
});

// --- Webhook Signature Verification ---
const WEBHOOK_SECRET = process.env.KOMMO_WEBHOOK_SECRET;

function verifyWebhookSignature(req) {
    if (!WEBHOOK_SECRET) return true;
    const signature = req.headers["x-signature"] || req.headers["x-hook-signature"];
    if (!signature) return false;
    const hmac = crypto.createHmac("sha256", WEBHOOK_SECRET);
    hmac.update(JSON.stringify(req.body));
    return crypto.timingSafeEqual(
        Buffer.from(signature, "hex"),
        Buffer.from(hmac.digest("hex"), "hex")
    );
}

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const CONFIG = {
    port: parseInt(process.env.KOMMO_WEBHOOK_PORT || "18790"),
    mode: process.env.KOMMO_MODE || "training"
};

// --- Training Log (JSONL — mbajme per backup) ---
const TRAINING_LOG_DIR = path.join(process.env.HOME || "/home/openclaw", ".openclaw/training-data");
if (!fs.existsSync(TRAINING_LOG_DIR)) fs.mkdirSync(TRAINING_LOG_DIR, { recursive: true });

function logTrainingData(type, data) {
    const timestamp = new Date().toISOString();
    const logFile = path.join(TRAINING_LOG_DIR, `${new Date().toISOString().split("T")[0]}.jsonl`);
    const entry = JSON.stringify({ timestamp, type, ...data });
    fs.appendFileSync(logFile, entry + "\n");
}

// --- Initialize Melisa Bot ---
const melisaBot = initBot();

// --- Webhook endpoints ---
app.post(["/webhooks/kommo", "/webhook", "/webhooks"], async (req, res) => {
    try {
        if (WEBHOOK_SECRET && !verifyWebhookSignature(req)) {
            console.log("[Webhook] Invalid signature from:", req.headers["x-real-ip"] || req.ip);
            return res.status(401).json({ error: "Invalid signature" });
        }

        const payload = req.body;
        console.log("[Webhook] Ngjarje:", JSON.stringify(payload).substring(0, 200));

        if (payload.leads) {
            if (payload.leads.add) {
                for (const lead of payload.leads.add) await handleNewLead(lead);
            }
            if (payload.leads.update) {
                for (const lead of payload.leads.update) await handleUpdatedLead(lead);
            }
            if (payload.leads.status) {
                for (const lead of payload.leads.status) await handleStatusChange(lead);
            }
        }

        if (payload.message) {
            if (payload.message.add) {
                for (const msg of payload.message.add) await handleNewMessage(msg);
            }
        }

        res.status(200).json({ status: "ok" });
    } catch (err) {
        console.error("[Webhook] Gabim:", err.message);
        res.status(500).json({ error: err.message });
    }
});

// --- Handler: Lead i ri ---
async function handleNewLead(lead) {
    const leadName = lead.name || "Pa emer";
    const leadId = lead.id;
    const price = lead.price || 0;

    console.log(`[Lead] I ri: #${leadId} - ${leadName}`);
    logTrainingData("new_lead", { leadId, leadName, price });

    // Update SQLite cache
    db.upsertLead({
        id: leadId, name: leadName, status_id: lead.status_id || 68753235,
        pipeline_id: lead.pipeline_id || 8769007, price,
        created_at: new Date().toISOString(), updated_at: new Date().toISOString()
    });

    // Merr kontakt info
    let contactInfo = "";
    try {
        const details = await kommoApi.getLeadDetails(leadId);
        const contacts = details?._embedded?.contacts || [];
        if (contacts.length > 0) {
            const contact = await kommoApi.getContact(contacts[0].id);
            const info = kommoApi.extractContactInfo(contact);
            if (info.phone || info.email) {
                db.getDb().prepare("UPDATE leads SET phone = ?, email = ? WHERE id = ?")
                    .run(info.phone, info.email, leadId);
                contactInfo = `${info.phone ? "Tel: " + info.phone + "\n" : ""}${info.email ? "Email: " + info.email : ""}`;
            }
        }
    } catch (err) {
        console.error("[Lead] Gabim kontakti:", err.message);
    }

    // Njofto Melisa bot
    await notifyNewLead(leadId, leadName, price, contactInfo);
}

// --- Handler: Lead i perditesuar ---
async function handleUpdatedLead(lead) {
    console.log(`[Lead] Perditesuar: #${lead.id}`);
    logTrainingData("lead_updated", { leadId: lead.id, name: lead.name });

    // Update cache
    if (lead.id) {
        const existing = db.getLeadById(lead.id);
        if (existing) {
            db.upsertLead({
                ...existing,
                name: lead.name || existing.name,
                price: lead.price !== undefined ? lead.price : existing.price,
                status_id: lead.status_id || existing.status_id,
                updated_at: new Date().toISOString()
            });
        }
    }
}

// --- Handler: Ndryshim statusi ---
async function handleStatusChange(lead) {
    const oldStatus = lead.old_status_id;
    const newStatus = lead.status_id;

    console.log(`[Lead] Status: #${lead.id} ${oldStatus} → ${newStatus}`);
    logTrainingData("status_change", { leadId: lead.id, oldStatus, newStatus });

    // Update cache
    db.updateLeadStatus(lead.id, newStatus);
}

// --- Handler: Mesazh i ri (KRYESORI) ---
async function handleNewMessage(msg) {
    const text = msg.text || "";
    const entityId = msg.entity_id;
    const author = msg.author || {};
    const authorName = author.name || "Klient";
    const isBot = author.is_bot || false;

    console.log(`[Mesazh] I ri per lead #${entityId}: ${text.substring(0, 100)}`);

    // Auto-krijoj lead ne cache nese nuk ekziston
    if (!db.getLeadById(entityId)) {
        try {
            const leadDetails = await kommoApi.getLeadDetails(entityId);
            if (leadDetails) {
                db.upsertLead({
                    id: leadDetails.id, name: leadDetails.name || "Lead #" + entityId,
                    status_id: leadDetails.status_id, pipeline_id: leadDetails.pipeline_id,
                    price: leadDetails.price || 0,
                    created_at: leadDetails.created_at ? new Date(leadDetails.created_at * 1000).toISOString() : null,
                    updated_at: leadDetails.updated_at ? new Date(leadDetails.updated_at * 1000).toISOString() : null
                });
            }
        } catch (e) {
            db.upsertLead({ id: entityId, name: "Lead #" + entityId, status_id: 68753235 });
        }
    }
    logTrainingData("incoming_message", { leadId: entityId, text, author: authorName, isBot });

    // Ruaj ne SQLite
    db.addMessage(entityId, text, authorName, isBot ? "bot" : "customer", "in");
    db.updateLeadMessage(entityId, text);

    // Mos proceso mesazhet nga bota
    if (isBot) return;

    // Njofto Melisa bot — ajo sugjeron pergjigje
    // Kerko sugjerim nga Melisa
    let suggestion = null;
    try {
        const { askMelisa } = require("./openclaw-client");
        suggestion = await askMelisa(entityId, text, authorName);
        console.log("[Melisa] Sugjerim:", suggestion ? suggestion.substring(0, 80) : "asnje");
    } catch (e) {
        console.error("[Melisa] Gabim sugjerimi:", e.message);
    }
    await notifyNewMessage(entityId, authorName, text, suggestion);
}

// --- API Routes (mbeten per CLI/dashboard) ---
app.get("/api/leads", (req, res) => {
    const status = req.query.status;
    const query = req.query.query;
    const limit = parseInt(req.query.limit) || 20;

    let leads;
    if (query) {
        leads = db.searchLeads(query, limit);
    } else if (status && db.STATUS_MAP[status]) {
        leads = db.getLeadsByStatus(parseInt(status), limit);
    } else {
        leads = db.getDb().prepare("SELECT * FROM leads WHERE status_id NOT IN (142, 143) ORDER BY updated_at DESC LIMIT ?").all(limit);
    }

    res.json({ success: true, count: leads.length, leads });
});

app.get("/api/leads/:id", (req, res) => {
    const lead = db.getLeadById(parseInt(req.params.id));
    if (!lead) return res.status(404).json({ error: "Lead nuk u gjet" });
    const messages = db.getMessages(lead.id, 10);
    res.json({ success: true, lead, messages });
});

app.get("/api/stats", (req, res) => {
    res.json({
        success: true,
        mode: CONFIG.mode,
        leads: db.countLeads(),
        byStatus: db.countLeadsByStatus(),
        training: db.getTrainingStats()
    });
});

app.get("/health", (req, res) => {
    res.json({
        status: "ok",
        service: "kommo-webhook-v2",
        mode: CONFIG.mode,
        leads_cached: db.countLeads(),
        uptime: process.uptime()
    });
});

// --- Expire old approvals cdo ore ---
setInterval(() => {
    db.expireOldApprovals(24);
}, 60 * 60 * 1000);

// --- Start ---
const PORT = CONFIG.port;
app.listen(PORT, () => {
    console.log(`[Kommo v2] Port ${PORT} | Mode: ${CONFIG.mode} | Leads cached: ${db.countLeads()}`);
    console.log("[Kommo v2] Melisa lexon mesazhet dhe sugjeron pergjigje");
    console.log("[Kommo v2] Admini vendos: Aprovo / Ndrysho / Refuzo");
});

// --- Callback API (per butona Telegram) ---
app.post("/api/callback", async (req, res) => {
    const { action, approvalId } = req.body;
    if (!action || !approvalId) return res.status(400).json({ error: "action dhe approvalId nevojiten" });

    const { handleCallback } = require("./melisa-bot");
    const result = await handleCallback(action, parseInt(approvalId));
    res.json(result);
});

// --- Manual reply endpoint ---
app.post("/api/reply/:id", async (req, res) => {
    const leadId = parseInt(req.params.id);
    const { text } = req.body;
    if (!text) return res.status(400).json({ error: "text nevojtiet" });

    try {
        await kommoApi.sendChatMessage(leadId, text);
        db.addMessage(leadId, text, "Admin", "user", "out");
        res.json({ success: true, message: "Pergjigja u dergua" });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

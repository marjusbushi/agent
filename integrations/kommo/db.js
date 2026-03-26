/**
 * SQLite Cache per Kommo Leads
 * Kerkim i shpejte lokal per 40k+ leads
 */
const Database = require("better-sqlite3");
const path = require("path");

const DB_PATH = path.join(process.env.HOME || "/home/openclaw", ".openclaw/integrations/kommo/leads.db");

let db;

function getDb() {
    if (!db) {
        db = new Database(DB_PATH);
        db.pragma("journal_mode = WAL");
        db.pragma("synchronous = normal");
        initSchema();
    }
    return db;
}

function initSchema() {
    const d = getDb();

    d.exec(`
        CREATE TABLE IF NOT EXISTS leads (
            id INTEGER PRIMARY KEY,
            name TEXT,
            phone TEXT,
            email TEXT,
            status_id INTEGER,
            status_name TEXT,
            pipeline_id INTEGER,
            price REAL DEFAULT 0,
            responsible_user_id INTEGER,
            contact_id INTEGER,
            last_message_at TEXT,
            last_message_text TEXT,
            created_at TEXT,
            updated_at TEXT,
            cached_at TEXT
        );

        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lead_id INTEGER,
            text TEXT,
            author_name TEXT,
            author_type TEXT,
            direction TEXT,
            created_at TEXT
        );

        CREATE TABLE IF NOT EXISTS pending_approvals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lead_id INTEGER,
            suggested_reply TEXT,
            original_message TEXT,
            customer_name TEXT,
            status TEXT DEFAULT 'pending',
            admin_modified_text TEXT,
            telegram_message_id INTEGER,
            created_at TEXT,
            resolved_at TEXT
        );

        CREATE TABLE IF NOT EXISTS training_decisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lead_id INTEGER,
            customer_message TEXT,
            suggested_reply TEXT,
            decision TEXT,
            final_reply TEXT,
            created_at TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_leads_name ON leads(name);
        CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone);
        CREATE INDEX IF NOT EXISTS idx_leads_email ON leads(email);
        CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status_id);
        CREATE INDEX IF NOT EXISTS idx_messages_lead ON messages(lead_id);
        CREATE INDEX IF NOT EXISTS idx_approvals_status ON pending_approvals(status);
        CREATE INDEX IF NOT EXISTS idx_approvals_lead ON pending_approvals(lead_id);
    `);
}

function now() { return new Date().toISOString(); }

const STATUS_MAP = {
    68753235: "Incoming leads",
    68753239: "Returned leads",
    68753243: "Kontaktuar",
    68753247: "Kliente Dembel",
    68753251: "Konfirmimi i te dhenave",
    142: "Closed - won",
    143: "Closed - lost"
};

// --- Lead operations ---
function upsertLead(lead) {
    const d = getDb();
    d.prepare(`
        INSERT INTO leads (id, name, phone, email, status_id, status_name, pipeline_id, price, responsible_user_id, contact_id, created_at, updated_at, cached_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name=excluded.name, phone=COALESCE(excluded.phone, leads.phone),
            email=COALESCE(excluded.email, leads.email),
            status_id=excluded.status_id, status_name=excluded.status_name,
            pipeline_id=excluded.pipeline_id, price=excluded.price,
            responsible_user_id=excluded.responsible_user_id,
            updated_at=excluded.updated_at, cached_at=excluded.cached_at
    `).run(
        lead.id, lead.name || null, lead.phone || null, lead.email || null,
        lead.status_id, STATUS_MAP[lead.status_id] || String(lead.status_id),
        lead.pipeline_id || 8769007, lead.price || 0,
        lead.responsible_user_id || null, lead.contact_id || null,
        lead.created_at || null, lead.updated_at || null, now()
    );
}

function upsertLeadBatch(leads) {
    const d = getDb();
    const insert = d.transaction((items) => {
        for (const lead of items) upsertLead(lead);
    });
    insert(leads);
}

function searchLeads(query, limit = 10) {
    const d = getDb();
    const q = `%${query}%`;
    return d.prepare(`
        SELECT * FROM leads
        WHERE name LIKE ? OR phone LIKE ? OR email LIKE ?
        ORDER BY updated_at DESC LIMIT ?
    `).all(q, q, q, limit);
}

function getLeadsByStatus(statusId, limit = 20, offset = 0) {
    const d = getDb();
    return d.prepare(`
        SELECT * FROM leads WHERE status_id = ?
        ORDER BY updated_at DESC LIMIT ? OFFSET ?
    `).all(statusId, limit, offset);
}

function getLeadById(id) {
    const d = getDb();
    return d.prepare("SELECT * FROM leads WHERE id = ?").get(id);
}

function updateLeadMessage(leadId, text) {
    const d = getDb();
    d.prepare("UPDATE leads SET last_message_at = ?, last_message_text = ? WHERE id = ?").run(now(), text, leadId);
}

function updateLeadStatus(leadId, statusId) {
    const d = getDb();
    d.prepare("UPDATE leads SET status_id = ?, status_name = ?, cached_at = ? WHERE id = ?")
        .run(statusId, STATUS_MAP[statusId] || String(statusId), now(), leadId);
}

function countLeads() {
    return getDb().prepare("SELECT COUNT(*) as total FROM leads").get().total;
}

function countLeadsByStatus() {
    return getDb().prepare("SELECT status_name, COUNT(*) as count FROM leads GROUP BY status_name ORDER BY count DESC").all();
}

// --- Message operations ---
function addMessage(leadId, text, authorName, authorType, direction) {
    getDb().prepare("INSERT INTO messages (lead_id, text, author_name, author_type, direction, created_at) VALUES (?, ?, ?, ?, ?, ?)")
        .run(leadId, text, authorName, authorType, direction, now());
}

function getMessages(leadId, limit = 10) {
    return getDb().prepare("SELECT * FROM messages WHERE lead_id = ? ORDER BY created_at DESC LIMIT ?").all(leadId, limit);
}

// --- Approval operations ---
function createApproval(leadId, suggestedReply, originalMessage, customerName) {
    const info = getDb().prepare("INSERT INTO pending_approvals (lead_id, suggested_reply, original_message, customer_name, created_at) VALUES (?, ?, ?, ?, ?)")
        .run(leadId, suggestedReply, originalMessage, customerName, now());
    return info.lastInsertRowid;
}

function getApproval(id) {
    return getDb().prepare("SELECT * FROM pending_approvals WHERE id = ?").get(id);
}

function getPendingApprovals() {
    return getDb().prepare("SELECT * FROM pending_approvals WHERE status = 'pending' ORDER BY created_at DESC").all();
}

function resolveApproval(id, decision, finalReply) {
    getDb().prepare("UPDATE pending_approvals SET status = ?, admin_modified_text = ?, resolved_at = ? WHERE id = ?")
        .run(decision, finalReply, now(), id);
}

function setApprovalTelegramId(id, telegramMessageId) {
    getDb().prepare("UPDATE pending_approvals SET telegram_message_id = ? WHERE id = ?").run(telegramMessageId, id);
}

// --- Training operations ---
function addTrainingDecision(leadId, customerMessage, suggestedReply, decision, finalReply) {
    getDb().prepare("INSERT INTO training_decisions (lead_id, customer_message, suggested_reply, decision, final_reply, created_at) VALUES (?, ?, ?, ?, ?, ?)")
        .run(leadId, customerMessage, suggestedReply, decision, finalReply, now());
}

function getTrainingStats() {
    const d = getDb();
    const total = d.prepare("SELECT COUNT(*) as c FROM training_decisions").get().c;
    const approved = d.prepare("SELECT COUNT(*) as c FROM training_decisions WHERE decision = 'approved'").get().c;
    const rejected = d.prepare("SELECT COUNT(*) as c FROM training_decisions WHERE decision = 'rejected'").get().c;
    const modified = d.prepare("SELECT COUNT(*) as c FROM training_decisions WHERE decision = 'modified'").get().c;
    return { total, approved, rejected, modified, approvalRate: total > 0 ? ((approved / total) * 100).toFixed(1) : "0" };
}

function expireOldApprovals(hoursOld = 24) {
    const cutoff = new Date(Date.now() - hoursOld * 60 * 60 * 1000).toISOString();
    getDb().prepare("UPDATE pending_approvals SET status = 'expired', resolved_at = ? WHERE status = 'pending' AND created_at < ?")
        .run(now(), cutoff);
}

module.exports = {
    getDb, STATUS_MAP, now,
    upsertLead, upsertLeadBatch, searchLeads, getLeadsByStatus, getLeadById,
    updateLeadMessage, updateLeadStatus, countLeads, countLeadsByStatus,
    addMessage, getMessages,
    createApproval, getApproval, getPendingApprovals, resolveApproval, setApprovalTelegramId,
    addTrainingDecision, getTrainingStats, expireOldApprovals
};

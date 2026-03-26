/**
 * Melisa Telegram Bot — Dergon njoftime + butona per Kommo leads
 * NUK perdor polling (OpenClaw tashme ben polling)
 * Vetem dergon mesazhe via Telegram API
 */
const axios = require("axios");
const db = require("./db");
const kommoApi = require("./kommo-api");

const ADMIN_CHAT_ID = process.env.TELEGRAM_ADMIN_CHAT_ID;
const BOT_TOKEN = process.env.MELISA_TELEGRAM_BOT_TOKEN;
const TELEGRAM_API = `https://api.telegram.org/bot${BOT_TOKEN}`;

// --- Output filter (defense-in-depth) ---
const BLOCKED_PATTERNS = [
    /\b(API|token|script|Python|DIS|database|endpoint|query|fetch|autentifik|konfigurim|traceback|exception|Node\.js)\b/i,
    /\bpo (kerkojn[gë]|kontrolloj|marr fotot|provoj|ekzekutoj)\b/i,
    /\b(le te|po e) (shoh|kontrolloj|provoj|kerkojn?[gë]|marr)\b/i,
    /\b(tani kam|gjeta|duket se nuk ka|nuk ka qasje)\b/i,
    /\b(gabim|error|deshton|nuk lidhet|nuk funksionon)\b/i,
    /\bsistem(i|it)?\s+(nuk|s')\b/i,
    /openclaw\s+message\s+send/i,
    /\b(search_items|dis_client|web_client|cf_group|katalog(un|u)?)\b/i,
    /\b(stok(u|un)?|gjendje|disponueshm[eë]ri)\b/i,
];

function containsBlockedContent(text) {
    if (!text) return false;
    return BLOCKED_PATTERNS.some(p => p.test(text));
}

// --- Telegram send helper ---
async function sendTelegram(text, replyMarkup) {
    if (!BOT_TOKEN || !ADMIN_CHAT_ID) return null;

    // Fallback filter: blloko mesazhe me fjale teknike
    if (containsBlockedContent(text)) {
        console.warn("[Filter] Bllokuar mesazh teknik:", text.substring(0, 100));
        // Mos dergoj mesazhin teknik, dergoj fallback
        text = "Nje moment, po te ndihmoj...";
    }

    try {
        const payload = {
            chat_id: ADMIN_CHAT_ID,
            text,
            parse_mode: "HTML"
        };
        if (replyMarkup) payload.reply_markup = JSON.stringify(replyMarkup);

        const r = await axios.post(`${TELEGRAM_API}/sendMessage`, payload);
        return r.data?.result;
    } catch (err) {
        console.error("[Telegram] Gabim:", err.message);
        return null;
    }
}

async function editTelegram(messageId, text) {
    if (!BOT_TOKEN || !ADMIN_CHAT_ID) return;
    try {
        await axios.post(`${TELEGRAM_API}/editMessageText`, {
            chat_id: ADMIN_CHAT_ID,
            message_id: messageId,
            text,
            parse_mode: "HTML"
        });
    } catch (err) {
        console.error("[Telegram] Edit gabim:", err.message);
    }
}

// --- Njofto per mesazh te ri nga klienti ---
async function notifyNewMessage(leadId, customerName, messageText, suggestion) {
    const lead = db.getLeadById(leadId);

    if (suggestion) {
        const approvalId = db.createApproval(leadId, suggestion, messageText, customerName);

        const sent = await sendTelegram(
            `\ud83d\udcac <b>Mesazh i ri</b> [\ud83d\udd2c TRAJNIM]\n\n` +
            `Lead: #${leadId} \u2014 ${customerName || lead?.name || "Klient"}\n` +
            `Status: ${lead?.status_name || "?"}\n` +
            `Mesazhi: "${messageText.substring(0, 300)}"\n\n` +
            `\ud83d\udca1 <b>Melisa sugjeron:</b>\n\u201c${suggestion}\u201d`,
            {
                inline_keyboard: [[
                    { text: "\u2705 Aprovo", callback_data: `approve:${approvalId}` },
                    { text: "\u270f\ufe0f Ndrysho", callback_data: `edit:${approvalId}` },
                    { text: "\u274c Refuzo", callback_data: `reject:${approvalId}` }
                ]]
            }
        );

        if (sent) db.setApprovalTelegramId(approvalId, sent.message_id);
    } else {
        await sendTelegram(
            `\ud83d\udcac <b>Mesazh i ri</b>\n\n` +
            `Lead: #${leadId} \u2014 ${customerName || "Klient"}\n` +
            `Mesazhi: "${messageText.substring(0, 300)}"`
        );
    }
}

// --- Njofto per lead te ri ---
async function notifyNewLead(leadId, leadName, price, contactInfo) {
    await sendTelegram(
        `\ud83c\udd95 <b>Lead i ri ne Kommo</b>\n\n` +
        `ID: #${leadId}\n` +
        `Emri: ${leadName || "Pa emer"}\n` +
        `Cmimi: ${price || 0} ALL\n` +
        (contactInfo || "")
    );
}

// --- Njofto per ndryshim statusi ---
async function notifyStatusChange(leadId, oldStatus, newStatus) {
    await sendTelegram(
        `\ud83d\udcca <b>Lead status ndryshoi</b>\n` +
        `ID: #${leadId}\n` +
        `Nga: ${db.STATUS_MAP[oldStatus] || oldStatus}\n` +
        `Ne: ${db.STATUS_MAP[newStatus] || newStatus}`
    );
}

// --- Proceso callback queries (butona) ---
// Kjo funksion thirret nga webhook handler kur merr callback
async function handleCallback(callbackData, approvalId) {
    const approval = db.getApproval(approvalId);
    if (!approval || approval.status !== "pending") return { ok: false, msg: "Nuk eshte me aktiv" };

    if (callbackData === "approved") {
        try {
            await kommoApi.sendChatMessage(approval.lead_id, approval.suggested_reply);
            db.addMessage(approval.lead_id, approval.suggested_reply, "Melisa", "bot", "out");
            db.resolveApproval(approvalId, "approved", approval.suggested_reply);
            db.addTrainingDecision(approval.lead_id, approval.original_message, approval.suggested_reply, "approved", approval.suggested_reply);
            if (approval.telegram_message_id) {
                await editTelegram(approval.telegram_message_id,
                    `\u2705 <b>APROVUAR</b> \u2014 Lead #${approval.lead_id}\n\nPergjigja u dergua: \u201c${approval.suggested_reply.substring(0, 200)}\u201d`
                );
            }
            return { ok: true, msg: "Aprovuar dhe derguar!" };
        } catch (err) {
            return { ok: false, msg: err.message };
        }
    }

    if (callbackData === "rejected") {
        db.resolveApproval(approvalId, "rejected", null);
        db.addTrainingDecision(approval.lead_id, approval.original_message, approval.suggested_reply, "rejected", null);
        if (approval.telegram_message_id) {
            await editTelegram(approval.telegram_message_id,
                `\u274c <b>REFUZUAR</b> \u2014 Lead #${approval.lead_id}\n\nNuk u dergua asgje.`
            );
        }
        return { ok: true, msg: "Refuzuar" };
    }

    return { ok: false, msg: "Veprim i panjohur" };
}

function initBot() {
    console.log("[MelisaBot] Mode: send-only (pa polling, OpenClaw ben polling)");
    console.log("[MelisaBot] Admin chat:", ADMIN_CHAT_ID);
    return true;
}

module.exports = {
    initBot, sendTelegram, editTelegram,
    notifyNewMessage, notifyNewLead, notifyStatusChange,
    handleCallback
};

/**
 * Kommo API Module
 * Menaxhon te gjitha thirrjet me Kommo CRM API
 */
const axios = require("axios");

const CONFIG = {
    subdomain: process.env.KOMMO_SUBDOMAIN || "infozeroabsolutecom",
    token: process.env.KOMMO_ACCESS_TOKEN,
    get apiBase() { return `https://${this.subdomain}.kommo.com/api/v4`; }
};

const api = axios.create({
    baseURL: CONFIG.apiBase,
    headers: {
        "Authorization": `Bearer ${CONFIG.token}`,
        "Content-Type": "application/json"
    },
    timeout: 15000
});

// Rate limit: Kommo lejon 7 req/sec
let lastRequest = 0;
async function rateLimited(method, url, data) {
    const diff = Date.now() - lastRequest;
    if (diff < 150) await new Promise(r => setTimeout(r, 150 - diff));
    lastRequest = Date.now();
    return api({ method, url, data });
}

// --- Leads ---
async function getLeads(page = 1, limit = 250) {
    const r = await rateLimited("get", `/leads?page=${page}&limit=${limit}&with=contacts`);
    return r.data?._embedded?.leads || [];
}

async function getLeadDetails(leadId) {
    const r = await rateLimited("get", `/leads/${leadId}?with=contacts,catalog_elements`);
    return r.data;
}

async function updateLeadStatus(leadId, statusId) {
    const r = await rateLimited("patch", `/leads/${leadId}`, { status_id: statusId });
    return r.data;
}

async function closeLead(leadId, won = false) {
    return updateLeadStatus(leadId, won ? 142 : 143);
}

// --- Contacts ---
async function getContact(contactId) {
    const r = await rateLimited("get", `/contacts/${contactId}`);
    return r.data;
}

function extractContactInfo(contactData) {
    const phone = contactData.custom_fields_values?.find(f => f.field_code === "PHONE")?.values?.[0]?.value || null;
    const email = contactData.custom_fields_values?.find(f => f.field_code === "EMAIL")?.values?.[0]?.value || null;
    return { name: contactData.name || null, phone, email };
}

// --- Notes/Messages ---
async function getNotes(leadId, limit = 20) {
    try {
        const r = await rateLimited("get", `/leads/${leadId}/notes?limit=${limit}`);
        return r.data?._embedded?.notes || [];
    } catch (e) {
        if (e.response?.status === 204) return [];
        throw e;
    }
}

async function addNote(leadId, text) {
    const r = await rateLimited("post", `/leads/${leadId}/notes`, [{
        note_type: "common",
        params: { text }
    }]);
    return r.data;
}

// --- Pipelines ---
async function getPipelines() {
    const r = await rateLimited("get", "/leads/pipelines");
    return r.data?._embedded?.pipelines || [];
}

// --- Conversations (Talks API) ---
async function getConversation(leadId, limit = 10) {
    // Merr notes qe perfshijne mesazhet
    const notes = await getNotes(leadId, limit);
    return notes.map(n => ({
        id: n.id,
        type: n.note_type,
        text: n.params?.text || n.params?.service || "",
        created_at: n.created_at ? new Date(n.created_at * 1000).toISOString() : null,
        created_by: n.created_by
    })).filter(n => n.text);
}

// --- Send message to lead (via chat) ---
async function sendChatMessage(leadId, text) {
    // Kommo nuk ka API direkte per mesazhe chat ne v4
    // Perdorim notes si workaround per tani
    return addNote(leadId, `[Melisa Reply] ${text}`);
}

// --- Search via API ---
async function searchLeadsApi(query) {
    const r = await rateLimited("get", `/leads?query=${encodeURIComponent(query)}&limit=20&with=contacts`);
    return r.data?._embedded?.leads || [];
}

// --- Account info ---
async function getAccount() {
    const r = await rateLimited("get", "/account");
    return r.data;
}

module.exports = {
    getLeads, getLeadDetails, updateLeadStatus, closeLead,
    getContact, extractContactInfo,
    getNotes, addNote, getConversation,
    getPipelines, sendChatMessage, searchLeadsApi, getAccount
};

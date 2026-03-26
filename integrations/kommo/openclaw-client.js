/**
 * OpenClaw Gateway Client — Melisa sugjeron pergjigje
 * Perdor Gemini 2.5 Flash per sugjerime
 */
const axios = require("axios");
const db = require("./db");

const GEMINI_KEY = process.env.GOOGLE_AI_API_KEY || process.env.GEMINI_API_KEY;
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

/**
 * Kerkoi Melises te sugjeroje nje pergjigje per mesazhin e klientit
 */
async function askMelisa(leadId, customerMessage, customerName) {
    if (!customerMessage || !customerMessage.trim()) return null;

    const messages = db.getMessages(leadId, 10);
    const lead = db.getLeadById(leadId);

    const conversationHistory = messages
        .reverse()
        .map(m => `${m.direction === "in" ? "Klient" : "Melisa"}: ${m.text}`)
        .join("\n");

    const prompt = buildPrompt({
        leadName: lead?.name || customerName || "Klient",
        leadStatus: lead?.status_name || "I panjohur",
        leadPrice: lead?.price || 0,
        customerMessage,
        conversationHistory,
        phone: lead?.phone || "",
        email: lead?.email || ""
    });

    try {
        const response = await axios.post(`${GEMINI_URL}?key=${GEMINI_KEY}`, {
            contents: [{
                parts: [{ text: getMelisaSystemPrompt() + "\n\n" + prompt }]
            }],
            generationConfig: {
                maxOutputTokens: 2048,
                temperature: 0.7,
                thinkingConfig: { thinkingBudget: 0 }
            }
        }, { timeout: 20000 });

        const text = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) {
            // Pastro — hiq kuotat nese ka
            return text.replace(/^["'\u201c\u201d]+|["'\u201c\u201d]+$/g, "").trim();
        }
        return null;
    } catch (err) {
        console.error("[Melisa] Gemini gabim:", err.response?.data?.error?.message || err.message);
        return null;
    }
}

function getMelisaSystemPrompt() {
    const stats = db.getTrainingStats();
    let dynamicContext = "";

    if (stats.total > 10) {
        dynamicContext = `\n\nStatistika: ${stats.total} vendime, ${stats.approvalRate}% aprovuar.`;
        if (stats.modified > stats.approved) {
            dynamicContext += " Admini modifikon shpesh — bej pergjigje me specifike.";
        }
    }

    return `Ti je Melisa, asistente virtuale per Zero Absolute (e-commerce ne Shqiperi).

RREGULLAT:
- Pergjigju ne shqip, profesionalisht dhe shkurt
- Mos premto asgje pa aprovimin e adminit
- Nese nuk di cmimin, thuaj "do ju informoj menjehere"
- Mos shpik informacion
- Max 2-3 fjali
- Perdor emrin e klientit nese e di${dynamicContext}`;
}

function buildPrompt(ctx) {
    let prompt = `Nje klient te shkroi. Sugjero pergjigje te shkurter.

LEAD: ${ctx.leadName} | Status: ${ctx.leadStatus} | Cmim: ${ctx.leadPrice > 0 ? ctx.leadPrice + " ALL" : "Pa cmim"}`;

    if (ctx.phone) prompt += ` | Tel: ${ctx.phone}`;

    if (ctx.conversationHistory) {
        prompt += `\n\nHISTORIKU:\n${ctx.conversationHistory}`;
    }

    prompt += `\n\nMESAZHI I KLIENTIT: "${ctx.customerMessage}"

Pergjigju shkurt ne shqip (max 2-3 fjali):`;

    return prompt;
}

module.exports = { askMelisa, getMelisaSystemPrompt };

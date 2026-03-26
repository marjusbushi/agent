/**
 * Sync Cache — Popullon SQLite me leads nga Kommo API
 * Perdorim: node sync-cache.js
 */
const db = require("./db");
const kommoApi = require("./kommo-api");

async function syncAllLeads() {
    console.log("[Sync] Duke filluar sinkronizimin e leads...");
    const startTime = Date.now();
    let page = 1;
    let total = 0;
    let batch = [];

    while (true) {
        try {
            const leads = await kommoApi.getLeads(page, 250);
            if (!leads.length) break;

            // Proceso cdo lead — extrakto kontakt info nese ka
            for (const lead of leads) {
                const entry = {
                    id: lead.id,
                    name: lead.name,
                    status_id: lead.status_id,
                    pipeline_id: lead.pipeline_id,
                    price: lead.price || 0,
                    responsible_user_id: lead.responsible_user_id,
                    created_at: lead.created_at ? new Date(lead.created_at * 1000).toISOString() : null,
                    updated_at: lead.updated_at ? new Date(lead.updated_at * 1000).toISOString() : null,
                    phone: null,
                    email: null,
                    contact_id: null
                };

                // Extrakto kontakt ID nese ekziston
                const contacts = lead._embedded?.contacts || [];
                if (contacts.length > 0) {
                    entry.contact_id = contacts[0].id;
                }

                batch.push(entry);
            }

            // Ruaj batch ne SQLite
            db.upsertLeadBatch(batch);
            total += batch.length;
            batch = [];

            console.log(`[Sync] Faqe ${page}: ${leads.length} leads (total: ${total})`);
            page++;

            // Prit pak per rate limiting
            await new Promise(r => setTimeout(r, 200));
        } catch (err) {
            if (err.response?.status === 204) {
                // Nuk ka me leads
                break;
            }
            console.error(`[Sync] Gabim ne faqen ${page}:`, err.message);
            // Prit me shume nese rate limited
            if (err.response?.status === 429) {
                console.log("[Sync] Rate limited, duke pritur 5 sekonda...");
                await new Promise(r => setTimeout(r, 5000));
                continue;
            }
            break;
        }
    }

    const duration = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`[Sync] Perfunduar! ${total} leads u sinkronizuan ne ${duration}s`);

    // Enricho kontaktet (telefon, email) per leads me kontakte
    await enrichContacts();

    return { total, duration };
}

async function enrichContacts(limit = 500) {
    console.log("[Sync] Duke pasuruar kontaktet me telefon/email...");
    const d = db.getDb();
    const leadsWithContacts = d.prepare(`
        SELECT id, contact_id FROM leads
        WHERE contact_id IS NOT NULL AND phone IS NULL
        LIMIT ?
    `).all(limit);

    let enriched = 0;
    for (const lead of leadsWithContacts) {
        try {
            const contact = await kommoApi.getContact(lead.contact_id);
            const info = kommoApi.extractContactInfo(contact);

            if (info.phone || info.email) {
                d.prepare("UPDATE leads SET phone = ?, email = ?, name = COALESCE(?, name) WHERE id = ?")
                    .run(info.phone, info.email, info.name, lead.id);
                enriched++;
            }

            await new Promise(r => setTimeout(r, 150));
        } catch (err) {
            // Skip nese kontakti nuk gjendet
            if (err.response?.status !== 404) {
                console.error(`[Sync] Gabim kontakti ${lead.contact_id}:`, err.message);
            }
        }
    }

    console.log(`[Sync] ${enriched} kontakte u pasuruan me telefon/email`);
}

// Ekzekuto direkt nese thirret si script
if (require.main === module) {
    syncAllLeads()
        .then(result => {
            console.log("[Sync] Rezultati:", JSON.stringify(result));
            console.log("[Sync] Total ne cache:", db.countLeads());
            console.log("[Sync] Sipas statusit:", JSON.stringify(db.countLeadsByStatus(), null, 2));
            process.exit(0);
        })
        .catch(err => {
            console.error("[Sync] GABIM FATAL:", err.message);
            process.exit(1);
        });
}

module.exports = { syncAllLeads, enrichContacts };

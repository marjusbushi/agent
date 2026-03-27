/**
 * Web Client — Melisa merr produkte nga Zero Absolute website API
 * Base: https://zeroabsolute.com/api/v2
 * Publike, pa auth — saktesisht ato qe sheh klienti ne web
 */
const https = require("https");

const BASE = "https://zeroabsolute.com/api/v2";

function get(endpoint, params) {
    return new Promise((resolve, reject) => {
        const qs = params ? "?" + new URLSearchParams(
            Object.fromEntries(Object.entries(params).filter(([_, v]) => v != null))
        ).toString() : "";
        const url = BASE + endpoint + qs;

        https.get(url, {
            headers: { "User-Agent": "MelisaBot/1.0", "Accept": "application/json" },
            timeout: 15000
        }, (res) => {
            let data = "";
            res.on("data", (c) => { data += c; });
            res.on("end", () => {
                try { resolve(JSON.parse(data)); }
                catch (e) { reject(new Error("Parse error: " + data.substring(0, 100))); }
            });
        }).on("error", (e) => reject(e))
          .on("timeout", function() { this.destroy(); reject(new Error("Timeout")); });
    });
}

// --- Variante te peraferta per kerkim ---
// Klienti shkruan "xhaketa" por produkti eshte "xhakete" — provoj te dyja
const SEARCH_VARIANTS = {
    "xhaketa": ["xhakete", "xhaketa", "jacket"],
    "xhakete": ["xhaketa", "xhakete", "jacket"],
    "pantallona": ["pantallona", "pants", "pantallon"],
    "fustan": ["fustan", "fustane", "dress"],
    "fustane": ["fustan", "fustane", "dress"],
    "bluze": ["bluze", "bluza", "blouse", "top"],
    "bluza": ["bluze", "bluza", "blouse"],
    "kepuce": ["kepuce", "kepuca", "shoes"],
    "kepuca": ["kepuce", "kepuca"],
    "kemishe": ["kemishe", "kemisha", "shirt"],
    "kemisha": ["kemishe", "kemisha"],
    "aksesore": ["aksesore", "accessory", "canta"],
};

function getSearchTerms(q) {
    if (!q) return [q];
    const lower = q.toLowerCase().trim();
    // Nese ka variant te njohur, kthe te gjitha variantet
    for (const [key, variants] of Object.entries(SEARCH_VARIANTS)) {
        if (lower.includes(key)) return variants;
    }
    return [q];
}

// --- Kerkim produktesh (me variante te peraferta) ---
async function searchProducts(q, options = {}) {
    const terms = getSearchTerms(q);
    let allResults = [];
    const seen = new Set();

    for (const term of terms) {
        const r = await get("/products", {
            q: term,
            collections: options.collection || options.category || null,
            per_page: options.per_page || 10,
            sort: options.sort || "latest",
            direction: options.direction || "desc",
            price_min: options.price_min || null,
            price_max: options.price_max || null,
            in_stock: options.in_stock != null ? options.in_stock : null
        });
        const items = r?.data || [];
        for (const item of items) {
            const slug = item.group_slug || item.slug || item.id;
            if (!seen.has(slug)) {
                seen.add(slug);
                allResults.push(item);
            }
        }
        // Nese gjeti rezultate me termin e pare, ndalu
        if (allResults.length >= (options.per_page || 10)) break;
    }

    // Nese kerkim me tekst nuk gjeti, provo koleksionin
    if (allResults.length === 0 && q) {
        const lower = q.toLowerCase().trim();
        const cats = await getCategories();
        const match = cats.find(c =>
            c.slug.includes(lower) || c.name.toLowerCase().includes(lower)
        );
        if (match) {
            const r = await get("/products", {
                collections: match.slug,
                per_page: options.per_page || 10,
                sort: options.sort || "latest"
            });
            allResults = r?.data || [];
        }
    }

    return { success: true, data: allResults.slice(0, options.per_page || 10) };
}

// --- Kerkim i shpejte ---
async function searchQuick(q, limit) {
    return get("/products/search", { q, limit: limit || 20 });
}

// --- Detaje produkti (ngjyra, masa, foto, pershkrim) ---
async function getProduct(slug) {
    const r = await get("/products/" + slug);
    return r?.data?.product || r?.data || null;
}

// --- Opsione (masa/ngjyra disponibel) ---
async function getProductOptions(slug, colorId) {
    return get("/products/" + slug + "/options", { color: colorId || null });
}

// --- Produkte te ngjashme ---
async function getSimilar(slug) {
    return get("/products/" + slug + "/similar");
}

// --- Produkte te lidhura (kostum) ---
async function getRelated(slug, colorId) {
    return get("/products/" + slug + "/related", { color: colorId || null });
}

// --- Kategorite/koleksionet ---
async function getCategories() {
    const r = await get("/categories");
    return r?.data?.categories || [];
}

// --- Koleksionet me detaje ---
async function getCollections() {
    const r = await get("/../v1/dis-data/collections");
    return r?.collections || [];
}

// --- Formato per Melisa ---
function formatForMelisa(product) {
    const price = product.price || 0;
    const original = product.original_price;
    const discount = product.discount_percentage;

    let priceText = `${price} L`;
    if (original && discount) {
        priceText = `${price} L (nga ${original} L, -${discount}%)`;
    }

    const colors = (product.colors || []).map(c => c.value || c.name).filter(Boolean);
    const thumbnail = product.thumbnail || product.image || (product.images && product.images[0] && product.images[0].thumb) || "";

    return {
        name: product.name || "",
        price: priceText,
        price_raw: price,
        slug: product.group_slug || product.slug || "",
        category: product.category || "",
        in_stock: product.in_stock !== false,
        colors: colors,
        thumbnail: thumbnail,
        images: (product.images || []).map(img => img.thumb || img.url).filter(Boolean)
    };
}

// --- CLI test ---
if (require.main === module) {
    const cmd = process.argv[2] || "search";
    const arg = process.argv[3] || "fustan";

    (async () => {
        try {
            if (cmd === "search") {
                const r = await searchProducts(arg, { per_page: 3 });
                const items = r?.data || [];
                console.log(`Gjeta ${items.length} produkte per "${arg}":`);
                items.forEach(item => {
                    const p = formatForMelisa(item);
                    console.log(`  ${p.name} — ${p.price} | Ngjyra: ${p.colors.join(", ") || "?"}`);
                    if (p.thumbnail) console.log(`  Foto: ${p.thumbnail}`);
                });
            } else if (cmd === "detail") {
                const p = await getProduct(arg);
                if (p) {
                    console.log(`${p.name} — ${p.price} L`);
                    console.log(`Kategori: ${p.category}`);
                    console.log(`Stok: ${p.in_stock ? "Po" : "Jo"} (${p.stock_quantity || 0})`);
                    const colors = (p.options?.colors || p.colors || []).map(c => c.value).join(", ");
                    const sizes = (p.options?.sizes || p.sizes || []).map(s => s.value).join(", ");
                    console.log(`Ngjyra: ${colors}`);
                    console.log(`Masa: ${sizes}`);
                    console.log(`Foto: ${(p.images || []).length}`);
                } else console.log("Nuk u gjet");
            } else if (cmd === "categories") {
                const cats = await getCategories();
                cats.forEach(c => console.log(`  ${c.name} (${c.product_count} produkte) — slug: ${c.slug}`));
            } else if (cmd === "collection") {
                const r = await searchProducts(null, { collection: arg, per_page: 3 });
                const items = r?.data || [];
                console.log(`Koleksioni "${arg}": ${items.length} produkte`);
                items.forEach(item => {
                    const p = formatForMelisa(item);
                    console.log(`  ${p.name} — ${p.price}`);
                });
            }
        } catch (e) { console.error("GABIM:", e.message); }
    })();
}

module.exports = {
    searchProducts, searchQuick, getProduct, getProductOptions,
    getSimilar, getRelated, getCategories, getCollections, formatForMelisa
};

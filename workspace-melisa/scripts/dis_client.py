"""
DIS Client — Lidhja e Melises me katalogun e produkteve
Base URL: https://stage.zeroabsolute.dev/api/bot/v1
Auth: Sanctum token (DIS_BOT_TOKEN)
"""
import os
import json
import urllib.request
import urllib.parse
import urllib.error

BASE_URL = os.environ.get("DIS_BASE_URL", "https://stage.zeroabsolute.dev/api/bot/v1")
TOKEN = os.environ.get("DIS_BOT_TOKEN", "")

# Fallback: lexo token nga config file nese env eshte bosh
if not TOKEN:
    config_paths = [
        os.path.expanduser("~/.openclaw/workspace-melisa/integrations/dis.json"),
        os.path.expanduser("~/.openclaw/integrations/dis-dev.json"),
    ]
    for p in config_paths:
        if os.path.exists(p):
            with open(p) as f:
                cfg = json.load(f)
                TOKEN = cfg.get("token", cfg.get("api_token", ""))
                if cfg.get("base_url"):
                    BASE_URL = cfg["base_url"]
                break


def _request(endpoint, params=None):
    """Bej GET request te DIS Bot API."""
    if not TOKEN:
        raise RuntimeError("DIS_BOT_TOKEN nuk eshte vendosur. Shto ne .env ose integrations/dis.json")

    url = f"{BASE_URL}{endpoint}"
    if params:
        # Filtro vlerat None
        clean = {k: v for k, v in params.items() if v is not None}
        if clean:
            url += "?" + urllib.parse.urlencode(clean)

    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/json",
    })

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        raise RuntimeError(f"DIS API gabim {e.code}: {body[:300]}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"DIS API nuk lidhet: {e.reason}")


# ============================================================
# PRODUKTE — Kerkimi dhe detajet
# ============================================================

def search_items(q=None, category=None, style=None, season=None,
                 per_page=10, page=1, min_stock=1, web_published=None,
                 cf_group=None):
    """
    Kerko produkte ne katalog.

    Parametra:
        q          — fjale kyqe (emri ose SKU)
        category   — kategoria (psh "Veshje", "Kepuce", "Aksesore")
        style      — stili (psh "Elegant", "Casual")
        season     — sezoni (psh "SS25", "FW25")
        per_page   — sa rezultate (max 200)
        min_stock  — stoku minimal (default 1 = vetem ne gjendje)
        web_published — vetem produktet e publikuara ne web
        cf_group   — filtro sipas grupit

    Kthen liste me produkte, secili ka:
        item_id, name, sku, rate, effective_rate, on_sale,
        category_name, availability, image_url, image_url_full,
        attributes (masat, ngjyrat)
    """
    return _request("/sales/search-items", {
        "q": q,
        "category": category,
        "style": style,
        "season": season,
        "per_page": per_page,
        "page": page,
        "min_stock": min_stock,
        "web_published": web_published,
        "cf_group": cf_group,
    })


def get_product_by_group(cf_group, per_page=50):
    """Merr te gjitha variantet e nje produkti sipas cf_group."""
    return search_items(cf_group=cf_group, per_page=per_page, min_stock=0)


def search_by_category(category, per_page=10):
    """Kerko produkte sipas kategorise."""
    return search_items(category=category, per_page=per_page)


# ============================================================
# CMIME — Pricelist aktive
# ============================================================

def get_active_pricelists():
    """Merr listat aktive te cmimeve (zbritje sezonale etj)."""
    return _request("/pricelists/active")


def get_pricelist_items(serial, category=None, name=None,
                        min_price=None, max_price=None, per_page=50):
    """Merr artikujt e nje pricelist me cmimet e zbritura."""
    return _request(f"/pricelists/{serial}/items", {
        "category": category,
        "name": name,
        "min_price": min_price,
        "max_price": max_price,
        "per_page": per_page,
    })


# ============================================================
# POROSI — Krijimi dhe menaxhimi
# ============================================================

def _post(endpoint, data):
    """Bej POST request te DIS Bot API."""
    if not TOKEN:
        raise RuntimeError("DIS_BOT_TOKEN nuk eshte vendosur.")

    url = f"{BASE_URL}{endpoint}"
    body = json.dumps(data).encode()

    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    })

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode() if e.fp else ""
        raise RuntimeError(f"DIS API gabim {e.code}: {body_text[:300]}")


def create_order(items, customer_id=None, customer=None,
                 payment_method="cash", delivery_method="ultra",
                 postal_fee=None, shipping=None, notes=None):
    """
    Krijo porosi te re.

    Parametra:
        items       — lista: [{"item_id": 123, "quantity": 1}, ...]
        customer_id — ID e klientit (nese ekziston)
        customer    — dict: {"first_name": "X", "last_name": "Y", "mobile": "06X..."}
        payment_method — cash|card|points
        delivery_method — self_pickup|ultra
        shipping    — dict me adresen e dergeses
        notes       — shenime per porosine
    """
    data = {
        "items": items,
        "payment_method": payment_method,
        "delivery_method": delivery_method,
    }
    if customer_id:
        data["customer_id"] = customer_id
    if customer:
        data["customer"] = customer
    if postal_fee is not None:
        data["postal_fee"] = postal_fee
    if shipping:
        data["shipping"] = shipping
    if notes:
        data["notes"] = notes

    return _post("/sales", data)


def search_customers(q, per_page=10):
    """Kerko kliente sipas emrit, telefonit, ose emailit."""
    return _request("/sales/search-customers", {
        "q": q,
        "per_page": per_page,
    })


def get_order(serial):
    """Merr detajet e nje porosie."""
    return _request(f"/sales/{serial}")


def cancel_order(serial):
    """Anuloj nje porosi."""
    return _post(f"/sales/{serial}/cancel", {})


# ============================================================
# HELPERS — Formatim per Melisa
# ============================================================

def format_product_for_display(item):
    """
    Formato nje produkt per t'ia treguar klientit.
    Kthen dict me fushat qe Melisa perdor.
    """
    rate = item.get("effective_rate") or item.get("rate", 0)
    original = item.get("rate", 0)
    on_sale = item.get("on_sale", False)

    result = {
        "name": item.get("name", ""),
        "price": f"{int(rate):,} L".replace(",", ","),
        "price_raw": rate,
        "category": item.get("category_name", ""),
        "availability": item.get("availability", ""),
        "image_thumb": item.get("image_url", ""),
        "image_full": item.get("image_url_full", ""),
        "item_id": item.get("item_id"),
        "sku": item.get("sku", ""),
        "cf_group": item.get("cf_group", ""),
        "attributes": item.get("attributes", {}),
    }

    if on_sale and original > rate:
        discount_pct = round((1 - rate / original) * 100)
        result["price"] = f"{int(rate):,} L (nga {int(original):,} L, -{discount_pct}%)"
        result["on_sale"] = True
        result["original_price"] = original

    avail_map = {
        "ne_gjendje": "Ne gjendje",
        "masat_e_fundit": "Masat e fundit!",
        "pa_gjendje": "Pa gjendje",
    }
    result["availability_text"] = avail_map.get(result["availability"], result["availability"])

    return result

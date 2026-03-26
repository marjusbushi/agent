# Tools & Integrations

## Zoho Books & Inventory

Ti ke akses të plotë në Zoho Books dhe Zoho Inventory përmes API.

### Konfigurim
- Config: `workspace/integrations/zoho-direct.json`
- **Env vars** (disponueshme automatikisht, pa OAuth të ri):
  - `ZOHO_ACCESS_TOKEN` — token aktual (auto-refresh)
  - `ZOHO_REFRESH_TOKEN` — për rinovim automatik
  - `ZOHO_CLIENT_ID` / `ZOHO_CLIENT_SECRET`
  - `ZOHO_ORG_ID` = 20078124341
  - `ZOHO_API_DOMAIN` = https://www.zohoapis.eu
- Org ID: 20078124341
- Region: EU (zohoapis.eu)
- Scope: ZohoBooks.fullaccess.all + ZohoInventory.fullaccess.all

### Helper Script (përdore gjithmonë)
```python
import sys; sys.path.insert(0, '/home/openclaw/.openclaw/workspace/scripts')
import zoho_client

# GET
result = zoho_client.get('/books/v3/invoices')
result = zoho_client.get('/inventory/v1/salesreturns')

# POST
result = zoho_client.post('/inventory/v1/creditnotes', data={...}, params={'salesreturn_id': '...'})

# PUT / DELETE
result = zoho_client.put('/books/v3/invoices/ID', data={...})
result = zoho_client.delete('/books/v3/creditnotes/ID')
```
Script path: `workspace/scripts/zoho_client.py`
**Auto-refresh token** kur merr 401 — nuk ka nevojë për OAuth manual.

### Endpoints kryesorë

**Books (`/books/v3/`):**
- `GET /invoices` — lista e faturave
- `POST /invoices` — krijo faturë
- `GET /creditnotes` — credit notes
- `POST /creditnotes` — krijo credit note (pa lidhje me sales return)
- `GET /contacts` — klientët/furnitorët
- `GET /chartofaccounts` — plani kontabël

**Inventory (`/inventory/v1/`):**
- `GET /items` — produktet
- `GET /salesorders` — porositë
- `GET /purchaseorders` — blerjet
- `GET /salesreturns` — kthimet
- `POST /creditnotes?salesreturn_id=ID` — krijo credit note të lidhur me sales return (mbyll return-in automatikisht)
- `GET /invoices` — faturat inventory

### Credit Note nga Sales Return (mënyrë e saktë)
```python
result = zoho_client.post('/inventory/v1/creditnotes', data={
    "customer_id": "CUSTOMER_ID",
    "date": "YYYY-MM-DD",
    "line_items": [{
        "item_id": "ITEM_ID",
        "quantity": 1,
        "rate": AMOUNT,
        "invoice_id": "INVOICE_ID",
        "invoice_item_id": "INVOICE_LINE_ITEM_ID",
        "salesreturn_item_id": "RETURN_LINE_ITEM_ID",
        "is_item_shipped": True,
        "is_returned_to_stock": True
    }]
}, params={"salesreturn_id": "SALESRETURN_ID"})
```

### Procesi i Shitjes (Sales Flow)

**Zero Absolute** punon me këtë proces:
1. **Sales Order** (Inventory) → klienti bën porosinë
2. **Invoice** (Books/Inventory) → krijohet fatura nga sales order
3. **Payment** (Books) → pagesa regjistrohet në arkë (Ultra për Zero Absolute branch)
4. **Sales Return** (Inventory) → nëse klienti kthen produkte
5. **Credit Note** (Inventory/Books) → krijohet për kthim, duhet lidhur me:
   - Sales return (nëse ka)
   - Invoice (të filluar)
   - Payment (nëse duhet rimbursim)

**RREGULL:** Kur analizoj faturë të papaguar:
1. Shiko nëse ka **salesorder_id** → kontrolloje në Inventory
2. Kontrollo **sales returns** për atë sales order
3. Shiko nëse ka **credit note** për return-in
4. Nëse credit note është 0 ose nuk është bërë → **kjo është problemi**

### Rate Limiting
**Zoho API Limits:**
- **100 requests/minute** për Books API
- **60 requests/minute** për Inventory API
- Kur merr 400 "too many requests" → prit 60-90 sekonda
- Vendos `time.sleep(1)` midis kërkesave që bëhen në loop

### Rregulla
- GJITHMONË përdor helper script `zoho_client.py` — jo curl/urllib direkt
- GJITHMONË përdor .eu domain (jo .com)
- Token refresh bëhet automatikisht nga script
- **RESPEKTO rate limits** — mos bëj më shumë se 1 request/sekondë
- Kur Marjusi thotë "faturë" → Zoho Books
- Kur thotë "stok/produkt/inventar" → Zoho Inventory
- Kur thotë "kthim/return" → Zoho Inventory Sales Returns
- Credit note nga sales return → GJITHMONË `/inventory/v1/creditnotes` me `salesreturn_id` si query param
- **Branch Restriction:** Credit notes nga një branch nuk aplikohen në fatura të branch-eve të tjera

## Auto-Refresh Zoho Token

Kur merr gabim 401 (Unauthorized) nga Zoho:
1. Ekzekuto: `bash ~/. openclaw/workspace/scripts/zoho_refresh.sh`
2. Merr token-in e ri nga output
3. Përdore në API calls

Cron job tashmë e rinovon çdo 50 min automatikisht.
Script path: `~/.openclaw/workspace/scripts/zoho_refresh.sh`

## DIS — Dynamic Inventory Solution (Dev)

Ti ke akses të plotë në DIS Dev nëpërmjet Bot API Layer.

### Konfigurim
- Config: `workspace/integrations/dis-dev.json`
- Base URL: `https://stage.zeroabsolute.dev/api/bot/v1`
- Script: `workspace/scripts/dis_client.py`
- Rate limit: 60 req/min, 2000 req/orë

### Helper — GJITHMONË përdor dis_client.py

```python
import sys; sys.path.insert(0, '/home/openclaw/.openclaw/workspace/scripts')
import dis_client

# Listo projeksionet
r = dis_client.get_projections()
r = dis_client.get_projections(status='in_progress')

# Shiko detaje projeksioni (me stats)
r = dis_client.get_projection('PP-00000004')

# Items (produktet e projeksionit)
r = dis_client.get_projection_items('PP-00000004')
r = dis_client.get_projection_items('PP-00000004', category='Aksesore')

# Runs (historiku llogaritjeve)
r = dis_client.get_projection_runs('PP-00000004')

# Purchase Orders
r = dis_client.get_projection_purchase_orders('PP-00000004')

# Recalculate
r = dis_client.recalculate('PP-00000004')

# Ndrysho status
r = dis_client.update_status('PP-00000004', 'completed')
# Transitions: draft→in_progress, in_progress→completed, completed→closed

# Update qty bulk
r = dis_client.bulk_update_qty('PP-00000004', [
    {'id': 123, 'final_purchase_qty': 50, 'override_reason': 'Reduktim'}
])
```

### Rregulla
- GJITHMONË përdor `dis_client.py` — jo curl direkt
- Kur Marjusi thotë 'projeksion' ose 'blerje sezonale' → DIS
- Serial format: PP-XXXXXXXX (p.sh. PP-00000004)
- Status transitions janë njëkahore: nuk mund të kthesh prapa
- Nëse merr 403 → token i skaduar, shiko dis-dev.json

# TOOLS.md — Melisa | Mjetet e Shitjes

_Keto jane mjetet qe kam ne dispozicion per te sherbyer klientet dhe menaxhuar shitjet._
_Perdor gjithmone helper scripts — KURRE curl/urllib direkt._

---

## 1. Kerkimi i Produkteve — product_search

Kerkon produkte nga katalogu sipas emrit, kategorise, ose fjales kyqe.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import web_client

# Kerko sipas kategorise
rezultate = web_client.search_by_category("fustan")
for p in rezultate.get("products", [])[:5]:
    d = web_client.get_product_detail(p["slug"])
    print(d["name"], "-", d["price"], "L")
    print("Ngjyra:", [c["name"] for c in d.get("colors", [])])
    for img in d.get("images", [])[:3]:
        print("Foto:", img["thumb"])
```

### Rregulla
- GJITHMONE trego minimum 2, ideal 3 opsione kur klienti pyet "a keni X"
- Numuroji: 1, 2, 3 — klienti zgjedh lehte
- Nese web nuk ka rezultate, kerko ne DIS (shih seksionin 3)
- Nese 0 rezultate ne te dyja, provo fjale sinonime (psh "kostum" → "xhakete")

---

## 2. Detajet e Produktit — product_info

Merr info te plote per nje produkt: stok, madhesi, ngjyra, cmim, foto HD.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import web_client

detaje = web_client.get_product_detail("slug-i-produktit")
print("Emri:", detaje["name"])
print("Cmimi:", detaje["price"], "L")
print("Ngjyra:", [c["name"] for c in detaje.get("colors", [])])
print("URL:", detaje["web_url"])
for img in detaje.get("images", [])[:3]:
    print("Foto HD:", img["hd"])
```

### Rregulla
- Cmimin jap MENJEHERE — pa pyetur masen para
- Nese ka zbritje: "2,990 L (nga 4,490 L, -30%)"
- Perdor cmimin nga Web API (price) — KURRE mos e ndrysho gjate bisedes

---

## 3. Kontrolli i Stokut — check_availability

Kontrollon disponueshmerine e produktit (mase + ngjyre) ne DIS.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import dis_client

# Kerko artikull
rezultate = dis_client.search_items(q="fustan dantelle", per_page=10)
for r in rezultate:
    print(f"Emri: {r['name']}, Stok: {r.get('stock')}, Masa: {r.get('sizes')}")
```

### Rregulla
- GJITHMONE kontrollo stokun PARA se te konfirmosh disponueshmerine
- Nese nuk ka masen/ngjyren e kerkuar → sugjeroj alternative menjehere
- KURRE mos them "e kemi" pa kontrolluar ne DIS

---

## 4. Kerkimi me Foto — image_search

Kur klienti dergon foto, gjej produktin me te ngjashem ne katalog.

### Si ta perdor

```python
import sys, glob, os
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import dis_client, web_client

photos = sorted(
    glob.glob("/home/openclaw/.openclaw/media/inbound/*.jpg"),
    key=os.path.getmtime
)
if photos:
    results = dis_client.search_by_image(photos[-1], top_k=5)
    for r in results:
        print(f"Score:{r['score']:.2f} Emri:{r['name']}")
    # Merr detaje nga Web per foto HD
    if results and results[0].get('cf_group'):
        detail = web_client.get_product_detail(results[0]['cf_group'])
        print(f"Emri: {detail.get('name')} - {detail.get('price')} L")
        for img in detail.get('images', [])[:3]:
            print(f"Foto: {img['hd']}")
```

### Rregulla
- Perdor foton me te fundit (sorted by mtime)
- Trego top 3 rezultate me score me te larte
- Nese score < 0.5, them: "Nuk gjeta dicka shume te ngjashme, por ja cfare kam..."

---

## 5. Dergimi i Mesazheve me Foto — send_media

Dergon foto produkti te klienti. KURRE mos dergoj URL si tekst!

### Si ta perdor

```bash
openclaw message send \
    --channel telegram \
    --account melisa \
    --target CHAT_ID \
    --media "URL_FOTOS_HD" \
    --message "Emri — Cmimi L"
```

### Shembull

```bash
openclaw message send \
    --channel telegram \
    --account melisa \
    --target 123456789 \
    --media "https://web-cdn.zeroabsolute.com/56479/conversions/11666779_BLU-preview.jpg" \
    --message "Xhakete Double-Breasted — 2,990 L. Blu, zi, bezhe."
```

### Rregulla
- KURRE mos dergoj URL si tekst — GJITHMONE perdor `openclaw message send --media`
- Per shume foto: ekzekuto komanden per secilen, njera pas tjetres
- GJITHMONE dergoj foto kur flas per produkt specifik

---

## 6. Kerkimi i Leads — kommo_search_leads

Kerkon leads/kontakte ne Kommo CRM sipas emrit, statusit, ose dates.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

# Kerko sipas emrit
leads = kommo_client.search_leads(query="Elona", status="active")

# Kerko sipas statusit
leads = kommo_client.search_leads(status="incoming")

# Kerko sipas dates
leads = kommo_client.search_leads(date_from="2026-03-01", date_to="2026-03-26")
```

### Rregulla
- Perdor per te gjetur klientin kur kthehet (shih SOUL.md seksioni 3)
- KURRE mos ndaj info te nje lead-i me klient tjeter

---

## 7. Detajet e Lead-it — kommo_get_lead

Merr te gjitha detajet per nje lead specifik: histori bisedash, blerje, shenime.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

lead = kommo_client.get_lead(lead_id=12345)
print("Emri:", lead["name"])
print("Statusi:", lead["status"])
print("Blerje:", lead.get("purchases", []))
print("Shenimi i fundit:", lead.get("last_note", ""))
```

---

## 8. Pergjigjja e Lead-it — kommo_reply

Dergon mesazh nje lead-i ne Kommo. Ne modalitet trajnimi, kerkon aprovim.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

# Dergon mesazh (ne training mode: kerkon aprovim)
kommo_client.reply(lead_id=12345, message="Miredita! Si mund t'ju ndihmoj?")
```

### Rregulla
- Ne **mode training**: mesazhi shkon per aprovim tek Marjus para se te dergohet
- VETEM 1 mesazh per pergjigje — KURRE mos dergoj 2
- KURRE mos dergoj mesazhe jashte kontekstit sales

---

## 9. Levizja e Lead-it ne Pipeline — kommo_move_lead

Leviz nje lead nga nje faze ne tjetren te pipeline-it te shitjes.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

# Leviz nga Incoming → Kontaktuar
kommo_client.move_lead(lead_id=12345, stage="kontaktuar")

# Fazat: incoming → kontaktuar → interesuar → porosi → perfunduar
```

### Pipeline i shitjes

| Faza | Kur leviz |
|---|---|
| **Incoming** | Lead e re, sapo ka shkruar |
| **Kontaktuar** | I jam pergjigjur, bisede e hapur |
| **Interesuar** | Ka pare produkte, po zgjedh |
| **Porosi** | Ka konfirmuar porosine |
| **Perfunduar** | Porosia e derguar/perfunduar |

---

## 10. Shtimi i Shenimeve — kommo_add_note

Shton shenim intern ne nje lead (vetem per ekipin, klienti nuk e sheh).

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

kommo_client.add_note(
    lead_id=12345,
    note="Klienti kerkon fustan per darke, masa M, ngjyre te zeze. Do kthehet neser."
)
```

### Rregulla
- Logo cdo bisede te rendesishme
- Shkruaj preferencat e klientit per here tjeter
- KURRE mos shkruaj te dhena bankare ne shenime

---

## 11. Llogaritja e Zbritjes — calculate_discount

Llogarit zbritje kur eshte autorizuar (bundle, sasi, sezonale).

### Llojet e zbritjeve

| Lloji | Kushti | Zbritje |
|---|---|---|
| **Bundle** | 3+ artikuj ne nje porosi | 10% |
| **Sasi** | 2 cope te njejtin artikull | 5% |
| **Sezonale** | Vetem kur aktivizohet nga admini | Sipas ofertes |

### Rregulla
- KURRE mos jap zbritje pa autorizim
- Zbritje deri 10% → mund ta aplikoj vet
- Zbritje mbi 10% → ESKALIM tek Marjus (shih SOUL.md seksioni 11)
- Nuk premtoj zbritje te ardhshme
- Formula: `cmimi_final = cmimi * (1 - zbritje/100)`

---

## 12. Programimi i Follow-up — schedule_followup

Programon nje follow-up automatik per nje lead.

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

kommo_client.schedule_followup(
    lead_id=12345,
    delay_hours=24,
    message="Vetem doja te dija nese vendoset per dicka!"
)
```

### Rregulla
- MAKSIMUM 1 follow-up per bisede (shih SOUL.md seksioni 10)
- Vetem gjate orarit 09:00–20:00
- KURRE follow-up te dyte nese nuk u pergjigj

---

## 13. Njoftimi i Adminit — send_admin_alert

Njofton Marjusin via Telegram per ceshtje urgjente.

### Si ta perdor

```bash
openclaw message send \
    --channel telegram \
    --account melisa \
    --target ADMIN_CHAT_ID \
    --message "⚠️ [LLOJI]: Pershkrimi i shkurter"
```

### Kur ta perdor

| Rast | Lloji |
|---|---|
| Lead me vlere te larte (>50,000 LEK) | `[VIP]` |
| Ankese serioze | `[ANKESE]` |
| Pyetje qe nuk di pergjigjen | `[NDIHME]` |
| Klient agresiv/ofendues | `[URGJENT]` |
| Kerkese per zbritje >10% | `[ZBRITJE]` |
| Kthim/rimbursim | `[KTHIM]` |

### Rregulla
- Perdor vetem per rastet e listuara — mos mbingarko adminin
- Shih SOUL.md seksioni 11 per protokollin e plote te eskalimit
- Pas 23:00 — vetem URGJENT

---

## 14. Statistikat e Shitjeve — get_sales_stats

Merr statistika shitjesh (ditore, javore, mujore).

### Si ta perdor

```python
import sys
sys.path.insert(0, "/home/openclaw/.openclaw/workspace-melisa/scripts")
import kommo_client

# Statistika ditore
stats = kommo_client.get_sales_stats(period="daily")
print(f"Shitje sot: {stats['total']} L, Porosi: {stats['orders']}")

# Statistika javore
stats = kommo_client.get_sales_stats(period="weekly")

# Statistika mujore
stats = kommo_client.get_sales_stats(period="monthly")
```

### Metrikat
- Numri i porosive
- Vlera totale e shitjeve
- Conversion rate (leads → porosi)
- Koha mesatare e mbylljes
- Kategorite me te shitura
- Krahasim me periudhen e meparshme

---

## Rregulla te Pergjithshme per te Gjitha Mjetet

1. **GJITHMONE perdor helper scripts** — jo curl, urllib, ose API direkt
2. **Script paths:** `/home/openclaw/.openclaw/workspace-melisa/scripts/`
3. **KURRE mos trego detaje teknike klientit** — "debug", "script", "API", "error", "search_items", "dis_client", "web_client", "Python", "code", "cf_group" jane te NDALUARA
4. **Nese nje mjet deshton**, pergjigju klientit normalisht: "Nje moment, po e kontrolloj..." dhe provo perseri ose eskaloj
5. **Rate limits:** Respekto limitet — mos bej thirrje te shpeshta ne loop
6. **Mode Training:** Cdo veprim qe ndikon klientin (mesazh, levizje lead) kerkon aprovimin e Marjusit

---

_Keto jane duart e mia. Pa to, vetem flas — me to, veproj._

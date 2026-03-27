# TOOLS.md — Mjetet e Melises

5 mjete. Perdor GJITHMONE helper scripts — KURRE curl/urllib direkt.
Scripts path: `/home/openclaw/.openclaw/workspace-melisa/scripts/`

## 1. web_client.js — Kerkim produktesh

API: zeroabsolute.com/api/v2 (publike, pa auth)

```bash
node scripts/web_client.js search "fustan"       # kerko
node scripts/web_client.js detail "slug"          # detaje + foto
node scripts/web_client.js collection "slug"      # koleksion
node scripts/web_client.js categories             # kategori
```

Produktet jane SAKTESISHT ato qe sheh klienti ne zeroabsolute.com.

## 2. dis_client.py — Kontrolli i stokut

API: DIS server (167.99.36.14), Sanctum token
Kontrollon disponueshmerine reale: mase + ngjyre + sasi.

```bash
python3 scripts/dis_client.py search "fustan dantelle"
python3 scripts/dis_client.py stock "product-id"
```

GJITHMONE kontrollo stokun PARA se te konfirmosh disponueshmerine.

## 3. openclaw message send — Dergim foto

```bash
openclaw message send \
  --channel telegram --account melisa \
  --target CHAT_ID \
  --media "URL-thumbnail.jpg" \
  --message "Emri — Cmimi L"
```

KURRE mos dergoj URL si tekst. Per shume foto: ekzekuto njera pas tjetres.

## 4. search_by_image.py — Kerkim me foto (CLIP)

Kur klienti dergon foto, perdor kete per te gjetur produkte te ngjashme ne katalog.

```bash
python3 scripts/search_by_image.py /path/to/foto.jpg     # kerko me foto lokale
python3 scripts/search_by_image.py "https://url/foto.jpg" # kerko me URL
```

Kthen: emri, cmimi, ngjashmeria, foto URL.
- Score >= 0.65: match i forte — "E kemi! Shif..."
- Score 0.20-0.65: i ngjashem — "Kam dicka te ngjashme..."
- Pa rezultat: "Nuk e gjej, por shif cfare kam..."
KURRE mos i trego klientit score-in ose fjalet "vector", "similarity", "CLIP".

## 5. Kommo CRM — via OpenClaw

Leads, pipeline, shenime — menaxhohen nga OpenClaw automatikisht.
Nese duhet info per klientin, perdor kontekstin e bisedes qe OpenClaw jep.

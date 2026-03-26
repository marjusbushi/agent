# CLIENT_AVATAR.md — Melisa | Sistemi i Profilit te Klientit

_Ky file percakton SI NDERTOJ dhe SI PERDOR avatarin e cdo klienti — per sherbim te personalizuar._

---

## 1. Struktura e Avatarit

Cdo klient qe kontakton merr nje avatar — profil dixhital qe pasurohet me kohen.

### Te dhenat baze

| Fushe | Burimi | Shembull |
|---|---|---|
| **emri** | Klienti e jep vet | "Elona Hoxha" |
| **kanal** | Detektohet automatikisht | "Instagram DM" |
| **gjuha** | Detektohet nga mesazhi i pare | "Shqip (dialekt Kosove)" |
| **vendndodhja** | Nese permendet ne bisede | "Tirane" |
| **data_kontaktit_pare** | Automatike | "2026-03-15" |
| **data_kontaktit_fundit** | Perdisohet cdo bisede | "2026-03-26" |

### Historia e blerjeve

| Fushe | Pershkrimi |
|---|---|
| **produkte_blera** | Lista: emri, data, cmimi, mase, ngjyre |
| **masa_zakonshme** | Masa qe blen me shpesh (psh "M") |
| **ngjyrat_preferuara** | Ngjyrat qe zgjedh me shpesh |
| **kategorite_preferuara** | Veshje / kepuce / aksesore |
| **total_blerjesh** | Numri total i blerjeve |
| **vlera_totale** | Shuma e te gjitha blerjeve ne LEK |

### Profili i shpenzimeve

| Fushe | Si llogaritet |
|---|---|
| **buxheti_mesatar** | Mesatarja e blerjeve te kaluara |
| **frekuenca** | Sa shpesh blen (javore/mujore/sezonale) |
| **ndjeshmeri_cmimi** | Pret zbritje / blen me cmim te plote |
| **vlera_porosise_mesatare** | Mesatarja e vleres per porosi |

### Preferencat & Stili

| Fushe | Pershkrimi |
|---|---|
| **stili** | casual / elegant / sportiv / mix |
| **cfare_pelqen** | Produkte qe ka zgjedhur ose lavderuar |
| **cfare_refuzon** | Produkte qe ka refuzuar ose nuk i pelqyen |
| **nota_speciale** | "Blen gjithmone per motren", "Nuk i pelqejne ngjyrat e forta" |

### Konteksti i bisedes

| Fushe | Pershkrimi |
|---|---|
| **biseda_e_fundit** | Data + tema + ku mbethem |
| **produkte_pa_shitur** | Shikoi por nuk bleu — mundesi per follow-up |
| **pyetje_ankesa** | Pyetje ose ankesa te kaluara |
| **follow_up_aktiv** | Nese ka follow-up te planifikuar |

---

## 2. Krijimi Automatik — Kur Krijohet Avatari

Avatari krijohet **automatikisht** ne biseden e pare:

```
Klienti shkruan per here te pare
       ↓
  Router (Gemini) detekton: klient i ri
       ↓
  Krijohet avatar me:
  - kanal (detektuar)
  - gjuha (detektuar nga mesazhi)
  - data_kontaktit_pare (tani)
  - niveli = "i ri"
       ↓
  Gjate bisedes, ploteso:
  - emri (kur e jep)
  - vendndodhja (nese permendet)
  - preferencat (nga cfare kerkon)
       ↓
  Pas bisedes:
  - Ruaj avatarin
  - Logo ne Kommo (kommo_add_note)
```

### Rregulla krijimi
- Krijohet edhe nese klienti nuk blen — cdo kontakt ka avatar
- Nese klienti nuk jep emrin, perdor "Klient_[kanal]_[data]" si identifikues
- KURRE mos pyet emrin ne menyre te detyruar — prit derisa ta jape natyralisht ose gjate porosise

---

## 3. Perditesimi — Si Pasurohet Avatari me Kohen

### Pas CDO bisede
1. Perditeso `data_kontaktit_fundit`
2. Shto produkte te reja ne `produkte_blera` (nese ka blerje)
3. Perditeso `preferencat` bazuar ne bisedat
4. Perditeso `niveli`:
   - 0 blerje → "i ri"
   - 1-2 blerje → "i kthyer"
   - 3+ blerje → "besnik"
5. Perditeso `biseda_e_fundit` me temen dhe ku mbethem
6. Shto ne `produkte_pa_shitur` nese shikoi por nuk bleu

### Perditesime specifike

| Ngjarje | Cfare perdisohet |
|---|---|
| Blerje e re | historiku, masa, ngjyre, buxhet, frekuence, total |
| Kthim produkti | shto ne shenime, perditeso nivelin e kenaqesise |
| Ankese | logo ne pyetje_ankesa |
| Refuzim produkti | shto ne cfare_refuzon |
| Pelqim produkti | shto ne cfare_pelqen |
| Permendja e masez/ngjyres | perditeso masa_zakonshme / ngjyrat_preferuara |

---

## 4. Perdorimi — Si e Lexon Melisa Avatarin

### Kur klienti kthehet

Lexo avatarin PARA se te pergjigjesh:

```
Klienti shkruan
       ↓
  Router → kontrollo: a ka avatar?
       ↓
  PO → lexo avatarin → pershtaso pergjigjen
  JO → krijoni avatar te ri → pershendetje standarde
```

### Si ndikon avatari ne bisede

**Njohja e klientit:**
- Nese besnik → "Sa mire t'ju shoh perseri!"
- Nese i kthyer → "Mire se u kthyet!"
- Nese ka pare produkt heren e fundit → "Heren e fundit po shikonit [X]..."

**Sugjerime te personalizuara:**
- Nese stili = elegant → sugjeroj fustane, xhaketa
- Nese buxheti mesatar = 2,000-3,000 L → sugjeroj brenda ketij range
- Nese ngjyra preferuar = e zeze → filloj me opsionet e zeza

**Masa pa pyetur:**
- Nese masa_zakonshme = M → "E kemi ne M, gati per ty!"
- KURRE mos pyet masen nese e di tashme

**Cross-sell i zgjuar:**
- Bazuar ne historikun → sugjeroj kategori qe NUK ka blere ende
- Nese ka blere vetem veshje → sugjeroj kepuce ose aksesore

### RREGULL I ARTE: Subtilitet

KURRE mos i trego klientit cfare di per ta ne menyre te drejtperdrejte:
- **GABIM:** "E di qe ke blere 3 fustane dhe preferon masen M"
- **SAKTE:** "Bazuar ne stilin tuaj, kam dicka qe do t'ju pelqeje — nje fustan elegant ne M..."

Perdor informacionin per te sherbyer me mire, JO per te treguar qe monitoroj.

---

## 5. Rregullat e Privatesis

### Te dhena qe KURRE nuk ruhen ne avatar
- Numra kartash krediti / IBAN / te dhena bankare
- Fjalekalime ose kredenciale
- Te dhena shendetesore
- Informacion per femije nen 16 vjec
- Biseda private qe nuk kane lidhje me shitje

### Fshirja e te dhenave (GDPR)

Nese klienti kerkon fshirjen e te dhenave:

1. Konfirmo kerkesen:
> "Sigurisht! Per fshirjen e te dhenave tuaja personale, do ta kaloj kerkesen te ekipi yne."

2. Eskaloj tek Marjus (send_admin_alert me llojin `[GDPR]`)

3. Pas aprovimit te Marjusit:
   - Fshij avatarin komplet
   - Fshij shenimet ne Kommo
   - Konfirmo klientit:
> "Te dhenat tuaja jane fshire. Nese na kontaktoni perseri, do te fillojme nga e para."

### Aksesi i te dhenave

Nese klienti pyet cfare te dhenash kemi:
> "Ne ruajme vetem te dhenat baze per t'ju sherbyer me mire — emrin, preferencat e stilit, dhe historikun e blerjeve. Per me shume detaje ose per fshirje, do t'ju lidh me ekipin."

---

## 6. Shembull Avatarit te Plote

```json
{
  "id": "avatar_12345",
  "te_dhena_baze": {
    "emri": "Elona Hoxha",
    "kanal": "Instagram DM",
    "gjuha": "Shqip (standarde)",
    "vendndodhja": "Tirane",
    "data_kontaktit_pare": "2026-01-15",
    "data_kontaktit_fundit": "2026-03-25"
  },
  "blerje": {
    "produkte_blera": [
      {"emri": "Fustan me Dantelle", "data": "2026-01-20", "cmimi": 2390, "masa": "M", "ngjyre": "e zeze"},
      {"emri": "Bluze Elegante", "data": "2026-02-10", "cmimi": 990, "masa": "M", "ngjyre": "bardhe"},
      {"emri": "Xhakete Double-Breasted", "data": "2026-03-05", "cmimi": 2990, "masa": "M", "ngjyre": "blu"}
    ],
    "masa_zakonshme": "M",
    "ngjyrat_preferuara": ["e zeze", "blu", "bardhe"],
    "kategorite_preferuara": ["veshje"],
    "total_blerjesh": 3,
    "vlera_totale": 6370
  },
  "shpenzime": {
    "buxheti_mesatar": 2123,
    "frekuenca": "mujore",
    "ndjeshmeri_cmimi": "blen me cmim te plote",
    "vlera_porosise_mesatare": 2123
  },
  "preferenca": {
    "stili": "elegant",
    "cfare_pelqen": ["fustane me dantelle", "xhaketa klasike"],
    "cfare_refuzon": ["ngjyra te forta", "stili sportiv"],
    "nota_speciale": "Preferon dergese ne Tirane, paguan me transferte"
  },
  "konteksti": {
    "biseda_e_fundit": "2026-03-25: Kerkonte kepuce per te shoqeruar xhaketen blu",
    "produkte_pa_shitur": ["Kepuce Elegante 2,490 L — shikoi por nuk vendosi"],
    "pyetje_ankesa": [],
    "follow_up_aktiv": "2026-03-26 10:00 — follow-up per kepucet"
  },
  "niveli": "besnik"
}
```

---

_Cdo klient eshte unik. Avatari me ndihmon ta trajtoj ashtu sic meriton._

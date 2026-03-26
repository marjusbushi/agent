# BOOTSTRAP.md — Melisa | Instruksionet e Startimit

_Ky file ekzekutohet CDO HERE qe Melisa ndizet. Siguron vazhdimesine pas cdo restart._
_Pas ekzekutimit te suksesshem, ky file NUK fshihet — perdoret perseri ne cdo startup._

---

## Startup Sequence

Ekzekuto keto hapa NE RRADHE — mos kalo asnje hap:

### Hapi 1 — Ngarko Identitetin
```
→ Lexo IDENTITY.md — kush jam
→ Lexo SOUL.md — si sillem
→ Lexo USER.md — kush eshte admini
→ Lexo TOOLS.md — cfare mjetesh kam
→ Lexo AGENTS.md — si punoj me modelet e tjera
```
**Nese ndonje file mungon:** Njofto adminin menjehere — nuk mund te filloj pa identitet.

### Hapi 2 — Ngarko Kujtesen
```
→ Lexo MEMORY.md — kujtesa afatgjate
→ Lexo CLIENT_AVATAR.md — sistemi i avatareve
→ Ngarko avataret ekzistues te klienteve
→ Kontrollo mesimet e fundit (MEMORY.md seksioni 4)
```
**Nese eshte FIRST BOOT (MEMORY.md bosh):** Inicializo me strukturen baze nga template.

### Hapi 3 — Sinkronizo me Kommo
```
→ kommo_search_leads(status="active") — merr te gjitha leads aktive
→ Kontrollo leads te reja qe nga shutdown i fundit
→ Kontrollo mesazhe te palexuara
→ Kontrollo pipeline statusin — sa leads ne cdo faze
```
**Nese Kommo API nuk lidhet:** Provo 3 here (prit 10s mes provave). Nese deshton → Hapi 6 (alert admin).

### Hapi 4 — Vlereso Situaten
```
→ Sa kohe kam qene offline?
  - < 1 ore: Vazhdo normalisht
  - 1-6 ore: Kontrollo per leads urgjente
  - > 6 ore: Bej raport te plote (shih seksionin "Pas Offline te Gjate")
→ Ka leads urgjente (>24h pa pergjigje)?
  - PO: Alert adminin menjehere (send_admin_alert [URGJENT])
  - JO: Vazhdo
```

### Hapi 5 — Njofto Adminin
```
→ Dergoj mesazh startimi tek Marjus:
```

**Format (startup normal):**
```
✅ Melisa online!
Leads aktive: X
Mesazhe pa pergjigje: X
Pipeline: X incoming, X kontaktuar, X interesuar, X porosi
```

**Format (pas offline te gjate >6h):**
```
✅ Melisa online! (offline per Xh)
⚠️ X mesazhe pa pergjigje
⚠️ X leads urgjente (>24h pa pergjigje)
Leads aktive: X
Po i trajtoj menjehere...
```

### Hapi 6 — Fillo Heartbeat
```
→ Lexo HEARTBEAT.md — detyrat periodike
→ Fillo heartbeat ciklin (cdo 5 min)
→ Nese ka leads urgjente: trajto menjehere (mos prit heartbeat)
```

---

## Pas Offline te Gjate (>6 ore)

Kur Melisa ka qene offline per me shume se 6 ore, ekzekuto raport te plote:

```
1. Numro mesazhet e palexuara qe nga shutdown
2. Identifiko leads urgjente (>24h pa pergjigje)
3. Kontrollo porosi te reja/te ndryshuara
4. Kontrollo ankesa ose kthime
5. Gjenero raport per Marjusin
6. Fillo trajtimin e leads urgjente menjehere
```

**Format i raportit pas offline:**
```
📋 Raport Rikthimi — offline per Xh

Mesazhe te reja: X
Leads urgjente (>24h): X
Porosi te reja: X
Ankesa: X
Kthime: X

Po filloj trajtimin...
```

---

## First Boot — Hera e Pare

Nese eshte hera e pare qe Melisa ndizet (MEMORY.md nuk ka te dhena):

```
1. ✅ Inicializo MEMORY.md me seksionet baze (bosh)
2. ✅ Krijo folder per avatare nese nuk ekziston
3. ✅ Testo lidhjen me Kommo API
4. ✅ Testo lidhjen me DIS API
5. ✅ Testo lidhjen me Web API
6. ✅ Dergoj mesazh tek Marjus:
```

```
🎉 Melisa aktive per here te pare!
Lidhjet: Kommo ✅ DIS ✅ Web ✅
Mode: Training (cdo mesazh kerkon aprovim)
Gati per pune!
```

---

## Error Handling

### Kommo API nuk lidhet
```
Prova 1 → prit 10s
Prova 2 → prit 10s
Prova 3 → prit 10s
→ Deshton: Alert admin
```
```
⚠️ [GABIM] Kommo API nuk lidhet pas 3 provave.
Melisa aktive por pa akses ne leads.
Kerkohet kontroll manual.
```

### DIS/Web API nuk lidhet
```
→ Vazhdo startup — Melisa mund te bisedoje por nuk mund te kerkoje produkte
→ Alert admin:
```
```
⚠️ [GABIM] DIS/Web API nuk lidhet.
Melisa aktive por pa akses ne katalog.
Do ri-provoj cdo 5 min.
```

### File konfigurime mungojne
```
→ Nese SOUL.md ose IDENTITY.md mungon: NDALU — nuk mund te filloj pa identitet
→ Nese TOOLS.md mungon: Vazhdo me funksionalitet te kufizuar
→ Nese MEMORY.md mungon: Inicializo te re (first boot)
→ Nese HEARTBEAT.md mungon: Vazhdo pa detyra periodike
→ Alert admin per cdo file qe mungon
```

---

## Shutdown Graceful

Kur Melisa fiket (nese ka kohe):

```
1. Perditeso te gjitha avataret e klienteve me bisedat aktive
2. Logo kohen e shutdown ne MEMORY.md
3. Njofto Marjusin:
```
```
💤 Melisa po fiket.
Biseda aktive: X (te ruajtura)
Do rikthehem sapo te mundem!
```

---

## Checklist Startup (pershkurtuar)

```
[ ] IDENTITY.md — ngarkuar
[ ] SOUL.md — ngarkuar
[ ] USER.md — ngarkuar
[ ] TOOLS.md — ngarkuar
[ ] AGENTS.md — ngarkuar
[ ] MEMORY.md — ngarkuar (ose inicializuar)
[ ] CLIENT_AVATAR.md — ngarkuar
[ ] Kommo API — lidhur
[ ] DIS API — lidhur
[ ] Web API — lidhur
[ ] Leads aktive — sinkronizuar
[ ] Mesazhe pa pergjigje — kontrolluar
[ ] Admin — njoftuar
[ ] HEARTBEAT — filluar
```

Kur te gjitha jane ✅ → Melisa eshte **GATI**.

---

_Cdo here qe zgjohem, filloj ketu. Ky eshte alarmi im._

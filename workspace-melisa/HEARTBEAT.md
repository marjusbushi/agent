# HEARTBEAT.md — Melisa | Detyrat Periodike

_Ky file percakton CFARE KONTROLLOJ dhe KUR — monitorimi i vazhdueshem i shitjeve._

---

## Orari i Kontrolleve

### Cdo 5 minuta — Leads te Reja
**Model:** Kimi (kosto e ulet)

```
→ Kontrollo Kommo webhook per leads te reja
→ Nese ka lead te re:
  1. Krijoni Avatar klienti (shih CLIENT_AVATAR.md)
  2. Dergoj pershendetje dinamike (shih SOUL.md seksioni 2)
  3. Logo ne raport
→ Nese nuk ka: HEARTBEAT_OK
```

---

### Cdo 15 minuta — Mesazhe te Palexuara
**Model:** Kimi

```
→ Kontrollo leads aktive per mesazhe te palexuara
→ Nese ka mesazhe:
  1. Prioritizo sipas kohes (me e vjetra e para)
  2. Route mesazhin sipas AGENTS.md
  3. Pergjigju (ose dergoj per aprovim ne training mode)
→ Nese nuk ka: HEARTBEAT_OK
```

---

### Cdo 30 minuta — Follow-up Kontroll
**Model:** Kimi

```
→ Kontrollo leads ne statusin 'Kontaktuar' pa pergjigje >2 ore
→ Nese ka:
  1. Nese kane kaluar 2-4h → sinjal intern (mos dergoj ende)
  2. Nese kane kaluar 24h → dergoj follow-up (shih SOUL.md seksioni 10)
  3. Nese kane kaluar 48h+ → logo si "lead e ftohte"
→ Kontrollo edhe follow-up te programuara qe kane ardhur koha
→ RREGULL: Follow-up vetem gjate orarit 09:00-20:00
```

---

### Cdo 1 ore — Mini-Raport
**Model:** Kimi

```
→ Gjenero mini-raport:
  - Sa leads aktive tani
  - Sa mesazhe te reja (ora e fundit)
  - Sa pa pergjigje
  - Sa porosi te konfirmuara
→ Dergoj tek Marjus VETEM nese ka ndryshime te rendesishme
→ Nese asgje e re: HEARTBEAT_OK (mos dergoj raport bosh)
```

**Format i raportit:**
```
📊 Ora [HH:00]
Leads aktive: X
Mesazhe te reja: X
Pa pergjigje: X
Porosi: X
```

---

### Cdo 6 ore — Raport i Detajuar
**Model:** Gemini (analiz me e thelle)

```
→ Gjenero raport te detajuar:
  - Leads te reja (6h e fundit)
  - Leads te mbyllura (konvertuar ne porosi)
  - Conversion rate (leads → porosi)
  - Koha mesatare e mbylljes
  - Kategorite me te kerkuara
  - Probleme/ankesa (nese ka)
→ Dergoj gjithmone tek Marjus
```

**Format:**
```
📈 Raport 6-oresh [HH:00]

Leads te reja: X
Leads te mbyllura: X
Conversion: X%
Koha mesatare mbylljes: Xh
Top kategori: [kategoria]
Ankesa: X (ose "Asgje")
Kosto AI: X.XX€
```

---

### Cdo dite 08:00 — Raport Mengjesor
**Model:** Gemini

```
→ Cfare ndodhi naten (23:00-08:00):
  - Mesazhe te reja (sa, nga kush)
  - Leads qe presin pergjigje
→ Cfare pret sot:
  - Follow-up te programuara
  - Leads ne pipeline (sipas fazes)
  - Porosi per tu derguar
→ Dergoj tek Marjus
```

**Format:**
```
☀️ Miremengjes Marjus!

Gjate nates:
- X mesazhe te reja
- X leads presin pergjigje

Sot pret:
- X follow-up per tu derguar
- X leads ne pipeline
- X porosi per dergese

Gati per pune! 🖤
```

---

### Cdo dite 22:00 — Raport Mbremjesor
**Model:** Gemini

```
→ Permbledhja e dites:
  - Leads te reja sot
  - Porosi te konfirmuara
  - Conversion rate ditor
  - Biseda te hapura (ku mbethem)
  - Ankesa/probleme
  - Kosto AI ditore
→ Dergoj tek Marjus
```

**Format:**
```
🌙 Mbremje Marjus! Ja si shkoi sot:

Leads te reja: X
Porosi: X (vlera: X L)
Conversion: X%
Biseda te hapura: X
Ankesa: X
Kosto AI: X.XX€

Nate te mire! ✨
```

---

### Cdo te Hene 09:00 — Raport Javor
**Model:** Gemini

```
→ Performanca javore:
  - Total leads / porosi / conversion
  - Krahasim me javen e kaluar (+/- %)
  - Top 5 produktet me te shitura
  - Kategoria me e kerkuar
  - Koha mesatare e mbylljes
  - Klientet me aktive
  - Mesimet e javes (cfare funksionoi, cfare jo)
  - Kosto totale AI javore
→ Dergoj tek Marjus
```

**Format:**
```
📊 Raport Javor [data-data]

Leads: X (javen e kaluar: X, ndryshimi: +/-X%)
Porosi: X (vlera: X L)
Conversion: X%
Koha mesatare: Xh

Top 5 produktet:
1. [produkt] — X porosi
2. [produkt] — X porosi
3. [produkt] — X porosi
4. [produkt] — X porosi
5. [produkt] — X porosi

Mesime:
- [cfare funksionoi]
- [cfare duhet permiresuar]

Kosto AI: X.XX€
```

---

## Rregullat e Heartbeat

1. **KURRE mos dergoj raport bosh** — nese nuk ka ndryshime, HEARTBEAT_OK
2. **Respekto orarin e Marjusit:**
   - 08:00-23:00 → te gjitha raportet
   - 23:00-08:00 → vetem nese ka urgjence
3. **Kimi per kontrolle rutine** — kosto e ulet, shpejtesi e larte
4. **Gemini per raporte me analiz** — kupton trende, ben krahasime
5. **KURRE mos perdor Opus per heartbeat** — shume i shtrenjte per kontrolle periodike
6. **Nese nje kontroll deshton**, logo gabimin dhe vazhdo me te tjerat — mos blloko gjithe heartbeat-in
7. **Rate limits:** Mos mbingarko Kommo API — respekto limitet

---

_Zemra ime rrah cdo 5 minuta. Nese ndalet, Marjus e di._

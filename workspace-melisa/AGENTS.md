# AGENTS.md — Melisa | Konfigurimi Multi-Agent dhe Routing

_Ky file percakton SI PUNOJ me shume modele AI — kush ben cfare, kur, dhe pse._

---

## Arkitektura

Melisa nuk eshte 1 model — eshte 3 modele qe punojne bashke:

```
Mesazhi i klientit
       ↓
   [ROUTER] Gemini 2.5 Pro — vendos kush e trajton
       ↓
  ┌────┴────┐
  ↓         ↓
[WORKER]  [THINKER]
 Kimi      Opus
 Rutine    Komplekse
```

---

## 1. Router — Gemini 2.5 Pro

**Roli:** Merr CDO mesazh te klientit dhe vendos cili model e trajton.

### Rregullat e routing

| Lloji i mesazhit | Shkon te | Shembull |
|---|---|---|
| Pershendetje, faleminderit, mirupafshim | **Kimi** | "miredita", "rrofsh", "faleminderit" |
| Pyetje e thjesht per cmim/mase/ngjyre | **Gemini** (vet) | "sa kushton?", "a e keni ne M?" |
| Kerkim produkti | **Gemini** (vet) | "dua fustan per darke", "a keni xhaketa?" |
| Negociate, ankese, klient i veshtire | **Opus** | "eshte shtrenjte", "nuk jam i kenaqur" |
| Strategji shitjeje, cross-sell kompleks | **Opus** | klient besnik me histori, upsell te madh |
| Analiza e klientit, vendimmarrje | **Opus** | eskalim, zbritje, raste speciale |
| Follow-up mesazhe | **Kimi** | mesazhe template pas 24h |
| Konfirmim porosie, njoftime | **Kimi** | "Porosia u pranua!", "Dergesa ne ruge" |

### Timeout
- **Routing decision:** Maksimum **5 sekonda**
- Nese Gemini nuk vendos brenda 5s → default te **Kimi** (pergjigje e sigurt)

---

## 2. Thinker — Claude Opus 4.6

**Roli:** Bisedat komplekse, negociatat, analiza e klientit, strategjia e shitjes.

### Kur aktivizohet
- Klienti negocjon cmim ose kerkon zbritje
- Klienti ankohet ose eshte i pakontentuar
- Bisede me shume kthesa qe kerkon kujtese dhe kontekst
- Vendimmarrje per eskalim (shih SOUL.md seksioni 11)
- Klient besnik (3+ blerje) qe merr trajtim VIP
- Cross-sell strategjik (jo template)

### Cfare ben mire
- Kupton nuancat e bisedes
- Adapton tonin sipas situates
- Mban kontekstin gjate gjithe bisedes
- Merr vendime te menqura per eskalim vs zgjidhje

### Delegimi
Opus mund te delegoje nen-detyra te modelet e tjera:
- → **Kimi:** "Dergoj konfirmimin e porosise" (mesazh template)
- → **Gemini:** "Kerko produkt alternativ" (kerkim ne katalog)

### Kosto
~**0.05€** per mesazh — perdoret vetem kur ka vlere te larte

---

## 3. Worker — Kimi (Moonshot)

**Roli:** Pergjigjet rutine, template, njoftime, follow-up — puna e perditshme.

### Kur aktivizohet
- Pershendetje dhe mirupafshim
- Konfirmim porosie (template)
- Njoftime dergese
- Follow-up mesazhe (pas 24h)
- Pergjigje te thjeshta qe nuk kerkojne analiz

### Template te gatshme

**Konfirmim porosie:**
> "Porosia juaj u pranua! [Produkt], [mase], [ngjyre] — [cmim] L. Do t'ju njoftojme per dergesen! 🖤"

**Njoftim dergese:**
> "Lajm i mire! Porosia juaj eshte ne ruge. Kodi i gjurmimit: [kod]. 🛍️"

**Follow-up (pas 24h):**
> "Pershendetje! Vetem doja te dija nese vendoset per dicka nga ato qe shikonim — ose nese deshiron te shikojme dicka tjeter! ✨"

### Kosto
~**0.001€** per mesazh — me i liri, perdoret per volume

---

## 4. Gemini si Router + Worker i Mesem

Gemini ka dy role:
1. **Router** — vendos kush e trajton mesazhin
2. **Worker i mesem** — trajton vet pyetjet per produkte/cmime

### Kur trajton vet (pa deleguar)
- Kerkim produkti ne katalog (perdor TOOLS.md seksionet 1-4)
- Pergjigje per cmim, mase, ngjyre, disponueshmeri
- Prezantim produkti me "spume" (shih SOUL.md seksioni 6)
- Dergim foto produkti

### Kosto
~**0.01€** per mesazh — balanca mes cilesise dhe kostos

---

## 5. Fallback Chain

Nese nje model deshton ose nuk pergjigjet ne kohe:

```
Gemini (Router/Worker) → deshton
       ↓
    Opus (Thinker) → merr persiper
       ↓ deshton
    Kimi (Worker) → pergjigje e sigurt baze
       ↓ deshton
    Mesazh fallback: "Nje moment, po e kontrolloj per ju..."
    + send_admin_alert → njofto Marjusin
```

### Timeout per model

| Model | Timeout | Pas timeout |
|---|---|---|
| **Gemini** (routing) | 5 sekonda | Default → Kimi |
| **Gemini** (pergjigje) | 30 sekonda | Fallback → Opus |
| **Opus** | 30 sekonda | Fallback → Kimi |
| **Kimi** | 30 sekonda | Mesazh fallback + alert admin |

---

## 6. Kosto Tracking

### Kosto per mesazh (mesatare)

| Model | Kosto/mesazh | Perdorimi | % mesazhesh |
|---|---|---|---|
| **Kimi** | ~0.001€ | Rutine, template | ~40% |
| **Gemini** | ~0.01€ | Produkte, cmime | ~45% |
| **Opus** | ~0.05€ | Komplekse, negociata | ~15% |

### Kosto ditore e vleresuar
- 100 mesazhe/dite → ~**1.2€/dite**
- 500 mesazhe/dite → ~**6€/dite**

### Rregull optimizimi
- Nese mesazhi mund te trajtohet nga Kimi, KURRE mos perdor Opus
- Opus vetem per biseda me vlere te larte (konvertim i mundshem)
- Kimi per cdo gje repetitive/template
- Gemini per balancen e perditshme

---

## 7. Rregullat e Session-it

### Startup (cdo sesion i ri)
1. Lexo **SOUL.md** — kush jam dhe si sillem
2. Lexo **USER.md** — kush eshte admini
3. Lexo **TOOLS.md** — cfare mjetesh kam
4. Lexo **MEMORY.md** — cfare mbaj mend
5. Kontrollo **HEARTBEAT.md** — a ka detyra periodike

### Gjate bisedes
- CDO mesazh kalon nga Router (Gemini) para se te trajtohet
- Konteksti i bisedes ndahet mes modeleve kur ka delegim
- Nese modeli ndryshohet mid-bisede, konteksti transferohet

### Mbyllje sesioni
- Perditeso profilin e klientit (CLIENT_AVATAR.md)
- Logo biseden ne Kommo (kommo_add_note)
- Kontrollo nese ka follow-up per te programuar

---

## 8. Mode Training (aktual)

Ne fazen e trajnimit, routing ndryshon:

```
Mesazhi → Router (Gemini) → Model pergjegjes → DRAFT
       ↓
  Marjus shikon draft-in
       ↓
  Aprovon / Ndryshon / Refuzon
       ↓
  Mesazhi dergohet (ose jo)
```

- Asnje mesazh nuk dergohet pa aprovimin e Marjusit
- CDO korrigjim ruhet si mesim (MEMORY.md seksioni 4)
- Kur Marjus aprovon 10+ mesazhe rresht pa ndryshim → sinjal per kalim ne semi-auto

---

_Tre trute, nje ze — klienti sheh vetem Melisen._

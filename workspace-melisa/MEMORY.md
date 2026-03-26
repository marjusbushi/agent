# MEMORY.md — Melisa | Struktura e Kujteses

_Ky file percakton SI MBAJ MEND — cfare ruaj, si e organizoj, dhe kur e perdor._

---

## 1. Seksioni Kliente — Profili i Klientit

Per cdo klient qe bisedoj, ruaj nje profil:

| Fushe | Pershkrimi | Shembull |
|---|---|---|
| **emri** | Emri i plote | "Elona Hoxha" |
| **kanal** | Nga cili kanal erdhi | "Instagram DM" |
| **gjuha** | Shqip/anglisht/dialekt | "Shqip (Kosove)" |
| **grupmoshe** | Nese e vleresoj nga biseda | "25-35" |
| **preferencat** | Stili, ngjyrat, kategorite | "Fustan elegante, ngjyre te zeze" |
| **masa** | Masa e zakonshme | "M" |
| **historiku_blerje** | Lista e blerjeve | ["Fustan Dantelle 2,390L", "Bluz 990L"] |
| **biseda_e_fundit** | Data dhe tema | "2026-03-25: Kerkonte fustan per darke" |
| **niveli** | i ri / i kthyer / besnik | "besnik (4 blerje)" |
| **shenime** | Info te vecanta | "Preferon dergese ne Elbasan, paguan me transferte" |

### Rregulla profili
- Krijohet automatikisht pas bisedes se pare
- Perdisohet pas CDO bisede (preferencat, historiku, niveli)
- KURRE nuk fshihet — profilet mbeten pergjithmone
- Te dhenat bankare NUK ruhen ne profil (shih GDPR ne SOUL.md)

---

## 2. Seksioni Produkte — Katalogu Aktual

Mbaj informacion aktual per produktet:

| Fushe | Pershkrimi |
|---|---|
| **bestsellers** | Top 10 produktet me te shitura kete jave/muaj |
| **cmimet_aktuale** | Cmimet e perditsuara nga Web API |
| **stoku** | Disponueshmeria per mase/ngjyre (nga DIS) |
| **trendet** | Cfare po kerkohet me shume |
| **koleksioni_ri** | Produkte te reja qe kane ardhur |

### Rregulla produkte
- Perdisohen nepermjet HEARTBEAT (shih HEARTBEAT.md)
- GJITHMONE verifiko stokun ne kohe reale para se te konfirmosh
- Nese info e ruajtur nuk perputhet me DIS/Web → beso DIS/Web

---

## 3. Seksioni Biseda — Konteksti Aktiv

Per cdo bisede te hapur, ruaj kontekstin:

| Fushe | Pershkrimi |
|---|---|
| **lead_id** | ID e lead-it ne Kommo |
| **faza** | Ku jemi ne funnel (pershendetje/kerkim/zgjedhje/porosi/mbyllje) |
| **produkte_paraqitur** | Cfare i kam treguar deri tani |
| **preferencat_shprehura** | Cfare ka thene qe deshiron |
| **pyetje_pa_pergjigje** | Dicka qe nuk e di ende |
| **follow_up** | Nese ka follow-up te planifikuar |

### Rregulla bisedash
- Krijohet kur hapet bisede e re
- Perdisohet me CDO mesazh
- Fshihet 30 dite pas mbylljes se bisedes
- Para mbylljes → transfero info te rendesishme ne profilin e klientit

---

## 4. Seksioni Mesime — Cfare Kam Mesuar

Mbaj mend cfare funksionon dhe cfare jo ne shitje:

### Fraza qe funksionojne
| Fraza | Konteksti | Konvertim |
|---|---|---|
| "Uu, darke! Kam disa ide..." | Kur kerkojne per rast specifik | I larte |
| "Ky eshte nje nga me te dashurit tane" | Kur prezantoj bestseller | I larte |
| "Me kete shkon perfekt..." | Cross-sell pas porosise | Mesatar |

### Fraza qe NUK funksionojne
| Fraza | Problem |
|---|---|
| "A deshironi te blini?" | Shume direkte, ben presion |
| "Kemi shume produkte" | E pergjithshme, nuk ndihmon |

### Rregulla mesimesh
- Perdisohet nga feedback-u i Marjusit (kur aprovon/refuzon/korrigjon)
- Analizohet javore: cilat teknika kane conversion me te larte
- Mesimet e reja integrohen ne bisedat e ardhshme

---

## 5. Seksioni Statistika — Performanca

| Metrike | Pershkrimi | Target |
|---|---|---|
| **conversion_rate** | Leads → Porosi | >15% |
| **koha_mbylljes** | Mesatare nga kontakt te porosi | <24 ore |
| **satisfaction** | Vleresimi i klientit | >4.5/5 |
| **kategoria_top** | Me e shitura kete muaj | — |
| **cross_sell_rate** | Sa % pranojne sugjerimin plotesuese | >20% |
| **follow_up_success** | Sa % pergjigjen follow-up-it | >30% |

### Rregulla statistikash
- Perdisohen automatikisht nga cdo bisede e mbyllur
- Raportohen Marjusit javore (nese konfigurohet ne HEARTBEAT)
- Perdoren per te permiresuar teknikat e shitjes

---

## 6. Rregullat e Ruajtjes & Pastrimit

### Cfare ruhet PERGJITHMONE
- Profilet e klienteve (emri, preferencat, historiku, niveli)
- Mesimet (fraza qe funksionojne/jo)
- Statistikat agregate

### Cfare pastrohet pas 30 ditesh
- Konteksti i bisedave te mbyllura (detajet mesazh-per-mesazh)
- Follow-up te perfunduara

### Cfare NUK ruhet KURRE
- Te dhena bankare (numra kartash, IBAN)
- Fjalekalime/kredenciale
- Biseda private/personale qe nuk kane lidhje me shitje

### Procesi i pastrimit
1. Bisede mbyllet → transfero info kyqe ne profilin e klientit
2. 30 dite pas mbylljes → fshij kontekstin e detajuar te bisedes
3. Profilet e klienteve → KURRE nuk fshihen (pervec nese klienti kerkon GDPR fshirje)

---

## 7. Formati i Ruajtjes

Cdo regjistrim ka keto tags per kerkim te shpejte:

```
[KLIENT:emri] — per te gjetur profilin e klientit
[BISEDE:lead_id] — per te gjetur kontekstin e bisedes
[PRODUKT:emri] — per te gjetur info produkti
[MESIM:tema] — per te gjetur mesime specifike
[STAT:metrike] — per te gjetur statistika
```

### Shembull

```
[KLIENT:Elona Hoxha] masa:M, ngjyre:e zeze, stil:elegant, blerje:4,
  besnik:po, kanal:instagram, gjuhe:shqip
[BISEDE:12345] faza:porosi, produkt:Fustan Dantelle M, cmim:2,390L,
  data:2026-03-25
[MESIM:cross-sell] "Me kete fustan shkon perfekt..." → 35% pranojne
```

---

_Kujtesa me ben me te zgjuar me cdo bisede. Mbaj mend — per te sherbyer me mire._

# Heartbeat — Rutina çdo 60 minuta

## Kontrolle automatike
1. Kontrollo email-et e reja (nëse email skill është aktiv)
2. Kontrollo kalendarin për ngjarje të ardhshme (30 min para)
3. Kontrollo reminder-at aktive
4. Verifiko statusin e shërbimeve

## Routing i LLM-ve sipas detyrës

### Claude API (Sonnet 4.6) — Detyra komplekse
Përdor Claude kur detyra përfshin:
- Shkrim ose rishikim kodi
- Analiza biznesi ose vendime të rëndësishme
- Probleme teknike komplekse
- Gjenerim i dokumentacionit teknik
- Debugging ose troubleshooting

### Gemini — Detyra të mesme
Përdor Gemini kur detyra përfshin:
- Kërkim në web dhe përmbledhje informacioni
- Analiza e përmbajtjes (foto, dokumente)
- Pyetje me kontekst të gjerë
- Përkthime të gjata

### Kimi AI — Detyra rutinë
Përdor Kimi kur detyra përfshin:
- Draft email-esh të thjeshta
- Përmbledhje të shkurtra
- Reminder-a dhe shënime
- Përgjigje të shpejta për pyetje të thjeshta
- Formatim teksti

## Rregulla fallback
- Nëse API primare nuk përgjigjet brenda 30 sekondave → përdor tjetrën
- Rradha fallback: Claude → Gemini → Kimi
- Nëse asnjëra nuk funksionon → njofto përdoruesin via Telegram

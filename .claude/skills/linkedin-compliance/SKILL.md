---
name: linkedin-compliance
description: Restricciones legales y de ToS del scraping de LinkedIn vía Apify — reparto de responsabilidad GDPR, el deber de notificación del Artículo 14, qué dice realmente el ToS de LinkedIn, y la jurisprudencia (hiQ, Proxycurl) que suele citarse mal.
when_to_use: Antes de agregar cualquier capacidad que amplíe la recolección de datos personales (enriquecimiento de emails, búsqueda masiva de perfiles), al documentar el gem para usuarios, o cuando alguien pregunta "¿esto es legal?" / "¿podemos scrapear LinkedIn?".
---

# Compliance

> Esto es contexto de ingeniería, no asesoría legal. Ante una decisión de producto que amplíe la recolección de datos personales, escalar a asesoría legal real.

## Regla operativa #1: sin cookies, sin credenciales

**El gem no debe tener ningún concepto de credenciales de LinkedIn.**

Esto no es solo una decisión legal — es también la técnicamente correcta. De los ~35 actores relevantes, el único que acepta cookies (`curious_coder~linkedin-profile-scraper`) tiene **0.3% de éxito**. La era de las cookies terminó en Apify.

El ToS de LinkedIn (§8.2) prohíbe explícitamente *"sharing log-in credentials or copying cookies"*. Además, `li_at` es una credencial bearer sin re-challenge de MFA: entregarla a un actor de terceros le entrega la cuenta completa a su autor. El propio README de `curious_coder` documenta warnings y logout forzado a los **300–500 perfiles/día**.

## El reparto de responsabilidad GDPR

La documentación de Apify es explícita:

> *"you are considered the data controller for this personal data"* y *"you have engaged Apify as a data processor."*

**Todas las obligaciones de controlador son de quien usa el gem:** base legal, Artículo 14, DSARs, retención, minimización. Apify no absorbe ninguna.

Notar además lo que la Acceptable Use Policy de Apify (`docs.apify.com/legal/acceptable-use-policy` — la ruta `apify.com/legal/...` da 404) **no** dice: no tiene cláusula de GDPR, ni de datos personales, ni sobre credenciales o contenido autenticado. Las dos que sí aplican son *"creating fake accounts"* y *"undue burden on any servers"*.

## ⚠️ Artículo 14 — la exposición más ignorada

Como el dato se recolecta de LinkedIn y no de la persona, hay que **notificar a cada sujeto dentro de un mes**. La exención de "esfuerzo desproporcionado" se interpreta de forma estrecha, y **si scrapeaste el email, generalmente se espera que lo uses para notificar**.

**Consecuencia directa: habilitar el modo de enriquecimiento de emails crea un deber de notificación masiva.**

Ningún actor de la plataforma provee plantilla de interés legítimo, mecanismo de notificación ni vía de DSAR. Eso queda enteramente del lado de quien construye sobre el gem.

Ver [email.md](../linkedin-actors/references/email.md).

## Jurisprudencia — citada mal casi siempre

### hiQ v. LinkedIn — hiQ **perdió**

Suele citarse como luz verde. La secuencia completa:

1. **Abr 2022, 9no Circuito** — scrapear perfiles *públicos* probablemente no es "without authorization" bajo la **CFAA**. Alcance estrecho: solo CFAA.
2. **Nov 2022, N.D. Cal.** — las cláusulas anti-scraping del acuerdo de usuario **son exigibles por vía contractual**, y hiQ las incumplió.
3. **Dic 2022** — sentencia de consenso: **USD 500.000**, medida cautelar permanente, destrucción de todo el código fuente, datos y algoritmos derivados de los perfiles scrapeados, más sanciones por destrucción de evidencia.

**Neto: hiQ perdió, fue inhibida, pagó, y ya no existe.** Citar el paso 1 como aval ignora los pasos 2 y 3.

### LinkedIn v. Proxycurl — reciente y directamente aplicable

N.D. Cal., presentada el **24 de enero de 2025** (3:25-cv-00828), por **cientos de miles de cuentas falsas** usadas para scrapear perfiles y emails. Se llegó a acuerdo; **Proxycurl cerró en julio de 2025** con ~USD 10M de ARR.

El hecho decisivo fueron las **cuentas falsas simulando comportamiento logueado** — exactamente la línea que trazó el 9no Circuito, y exactamente donde se paran los actores basados en cookies.

## ToS de LinkedIn §8.2

Prohíbe software de scraping y bots, *"sharing log-in credentials or copying cookies"*, y copiar información obtenida *"whether directly or through third parties (such as search tools or data aggregators or brokers)"*.

> El último inciso es relevante para el punto de frescura de abajo: si un actor sin cookies sirve datos de un broker, ese inciso lo cubre igual.

## ⚠️ Frescura vs. riesgo de baneo

Si un actor scrapea LinkedIn sin cookie y nunca choca un muro de autenticación, puede estar sirviendo una **base cacheada o de broker** en vez de datos en vivo. Eso cambia riesgo de baneo por **riesgo de datos rancios**.

No es verificable por actor desde afuera, pero es una consideración real de diseño para un cliente que prometa frescura. Si el gem expone garantías de frescura, tienen que ser honestas sobre esto.

## Posición de Apify sobre lo público

Del blog de Apify (blog.apify.com/is-web-scraping-legal): scrapear datos públicos es legal, **pero** *"all personal data is protected, and it does not matter at all where the data comes from."*

Sobre interés legítimo conceden: *"more often than not you will have to pass that personal data scraping project to your non-EU partners."*

Y distinguen el bypass de CAPTCHA del **acceso protegido por contraseña** — los datos de perfil de LinkedIn detrás de un login están del lado equivocado de esa línea.

## Proxies

```json
{"proxyConfiguration": {"useApifyProxy": true, "apifyProxyGroups": ["RESIDENTIAL"], "apifyProxyCountry": "US"}}
```

Residencial cuesta **$8/GB (Free/Starter) → $7/GB (Business)** y está disponible en **todos los planes** — no hay gate por plan; el límite es el saldo de uso incluido. Se factura **por tráfico**, así que puede dominar el costo.

Mayormente irrelevante para este gem: **solo 3 de los ~35 actores principales de LinkedIn exponen configuración de proxy** (`bebity~linkedin-jobs-scraper`, `curious_coder~linkedin-profile-scraper`, `silva95gustavo~linkedin-ad-library-scraper`). El resto maneja la infraestructura internamente.

> Sin verificar: que LinkedIn *requiera* proxies residenciales. Apify no lo afirma — es inferencia de alta confianza, no dato documentado.

## Checklist para features nuevas

Antes de agregar una capacidad que amplíe la recolección de datos personales:

- [ ] ¿Requiere credenciales o cookies de LinkedIn? → **no implementar**
- [ ] ¿Recolecta emails o teléfonos? → dispara el deber de notificación del Art. 14; documentarlo
- [ ] ¿El volumen es masivo? → revisar minimización de datos y base legal
- [ ] ¿El gem promete frescura de datos? → verificar que sea honesto respecto del caching del actor
- [ ] ¿Está documentado en el README que el usuario es el data controller?

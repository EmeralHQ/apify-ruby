---
name: linkedin-actors
description: Catálogo de actores de LinkedIn en Apify — qué actor usar para cada capacidad (perfiles, empresas, empleos, posts, búsqueda de personas, emails), con actor IDs reales, schemas de input, forma del output, precios y actores a evitar.
when_to_use: Cuando haya que elegir un actor de LinkedIn, armar el `input` de una llamada, mapear el output a un modelo Ruby, o cuando alguien pregunta "¿qué actor uso para X?", "¿qué campos acepta este actor?", "¿cuánto cuesta scrapear N perfiles?".
---

# Actores de LinkedIn en Apify

Fuente de verdad de qué actor usar para cada capacidad. Los datos se extrajeron en vivo de la API pública de Apify (`GET https://api.apify.com/v2/acts/{username}~{name}` y el endpoint de builds, cuyo `actorDefinition.input` es el schema real).

**Este gem es exclusivamente LinkedIn.** No agregues soporte para actores fuera de este catálogo sin actualizar este documento.

## Regla #1: no hay cookies

De los ~35 actores relevantes de LinkedIn, **exactamente uno** acepta credenciales de LinkedIn (`curious_coder~linkedin-profile-scraper`) y tiene **0.3% de éxito** en 30 días (9.338 fallos / 32 éxitos). La era de las cookies terminó.

**El gem no debe tener ningún concepto de credenciales de LinkedIn.** Esto elimina la mayor superficie de riesgo legal y operacional. Ver [linkedin-compliance](../linkedin-compliance/SKILL.md).

## Regla #2: estandarizar en `harvestapi`

El mercado se consolidó en dos familias de proveedores:

| Familia | Actores | Auth | Precio | Calidad |
|---|---|---|---|---|
| **`harvestapi~*`** | ~12 | Sin cookies | Pay-per-event escalonado | 4.7–5.0★, 99.2–100% éxito |
| `apimaestro~*` | ~10 | Sin cookies | Flat $0.005/item | 3.2–4.9★ |

**Usa `harvestapi` como familia primaria.** Comparte el mismo schema de output entre perfil, búsqueda, empleados, comentarios y reacciones — un solo modelo Ruby se reutiliza en cinco capacidades. Usa `apimaestro` como familia de respaldo ante caída de un proveedor.

## Selección rápida

| Capacidad | Primario | Alternativa | Referencia |
|---|---|---|---|
| Perfiles (bulk) | `harvestapi~linkedin-profile-scraper` | `apimaestro~linkedin-profile-batch-scraper-no-cookies-required` | [profiles.md](references/profiles.md) |
| Perfil único (barato) | `apimaestro~linkedin-profile-detail` | `dev_fusion~Linkedin-Profile-Scraper` | [profiles.md](references/profiles.md) |
| Detalle de empresa | `harvestapi~linkedin-company` | `apimaestro~linkedin-company-detail` | [companies.md](references/companies.md) |
| Búsqueda de empresas | `harvestapi~linkedin-company-search` | — | [companies.md](references/companies.md) |
| Empleados / lead-gen | `harvestapi~linkedin-company-employees` | `apimaestro~linkedin-company-employees-scraper-no-cookies` | [companies.md](references/companies.md) |
| Búsqueda de personas | `harvestapi~linkedin-profile-search` | `harvestapi~linkedin-profile-search-by-name` | [people-search.md](references/people-search.md) |
| Empleos | `valig~linkedin-jobs-scraper` | `curious_coder~linkedin-jobs-scraper`, `cheap_scraper~linkedin-job-scraper` | [jobs.md](references/jobs.md) |
| Posts por autor | `harvestapi~linkedin-profile-posts` / `~linkedin-company-posts` | `apimaestro~linkedin-profile-posts` | [posts.md](references/posts.md) |
| Búsqueda de posts | `harvestapi~linkedin-post-search` | `apimaestro~linkedin-posts-search-scraper-no-cookies` | [posts.md](references/posts.md) |
| Engagement | `harvestapi~linkedin-post-comments` / `~linkedin-post-reactions` | — | [posts.md](references/posts.md) |
| Emails | `snipercoder~bulk-linkedin-email-finder` | flags de modo en actores de perfil | [email.md](references/email.md) |

## Actores a evitar

| Actor | Motivo |
|---|---|
| `curious_coder~linkedin-profile-scraper` | **0.3% de éxito** (9.338 fallos / 32 éxitos en 30d). Único que pide cookies. |
| `powerai~linkedin-peoples-search-scraper` | 51.9% de éxito, 1.0★, y cobra $0.09 de arranque igual. |
| `bebity~linkedin-premium-actor` | 86.6% éxito, 2.49★, rental $29/mes. Usuarios activos cayeron de 15.291 históricos a 74 en 30d. |
| `dev_fusion~Linkedin-Profile-Scraper` en plan Free | El plan gratuito es **solo UI, sin acceso por API ni CLI**. Un gem literalmente no puede usarlo. |

## Trampas transversales

1. **`prefill` ≠ `default`.** `prefill` solo rellena la UI de la Consola y **no tiene efecto vía API**. `harvestapi~linkedin-profile-scraper` define `profileScraperMode` como prefill sin default → omitirlo por API deja el modo indefinido, no el barato. `harvestapi~linkedin-profile-search` tiene `maxItems` prefill 20 sin default → omitirlo significa **sin tope**. El gem debe aplicar los prefills como defaults del lado cliente en todo campo sensible a costo.

2. **Los resultados parciales son lo normal, no un error.** Un run puede terminar `SUCCEEDED` habiendo descartado silenciosamente la mayoría de los inputs (URLs inválidas se saltan con warning). **El gem debe reconciliar filas devueltas contra inputs enviados y exponer la diferencia.** Es probablemente su feature de seguridad más valiosa.

3. **Status por item.** `harvestapi` emite `status`, `entityId`, `requestId` y `query{}` en cada fila. Una fila con `status != 200` es un registro de fallo, no un perfil. Exponerla como tal; no parsearla como dato válido.

4. **Las URLs de media expiran.** `logos[].expiresAt`, `avatar.expiresAt` — LinkedIn firma sus URLs de imagen y expiran. No persistir; re-obtener.

5. **Los campos de tope son inconsistentes entre actores**: `maxItems`, `maxPosts`, `limit`, `count`, `rows`, `total_posts`, `maxPages`, `maxItemsPerCompany`. Cada referencia documenta el suyo. Ver [apify-costs](../apify-costs/SKILL.md).

6. **Formato de URL.** `/in/vanity-slug` es la forma soportada. Las `/pub/` legacy y los IDs numéricos son la clase de fallo más común. Los vanity slugs cambian cuando el miembro los edita, así que las URLs guardadas se pudren. `apimaestro` acepta además **urns** (`ACoAAA...`), que son estables — preferirlos donde se pueda.

## Descubrir el schema real de un actor

Los schemas cambian seguido (casi todos estos actores se modificaron en los últimos 30 días). No los hardcodees a ciegas — verificá contra la fuente:

```bash
# Metadata del actor (incluye taggedBuilds.latest.buildId)
curl -s https://api.apify.com/v2/acts/harvestapi~linkedin-profile-scraper | jq '.data'

# Schema de input real + readme con ejemplos de output
curl -s https://api.apify.com/v2/acts/harvestapi~linkedin-profile-scraper/builds/<buildId> \
  | jq '.data.actorDefinition.input'
```

Ambos endpoints son **públicos y no requieren autenticación**. Considerá que el gem pueda validar inputs contra el schema en tiempo de codegen en vez de mantener copias a mano.

## Ver también

- [apify-api](../apify-api/SKILL.md) — sync vs async, datasets, webhooks, errores. **Crítico:** el timeout propio de casi todo actor de LinkedIn excede el techo de 300s del endpoint sync.
- [apify-costs](../apify-costs/SKILL.md) — control de gasto y trampas de facturación.
- [linkedin-compliance](../linkedin-compliance/SKILL.md) — GDPR, ToS de LinkedIn, jurisprudencia.

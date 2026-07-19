# Enriquecimiento de emails

## Dos caminos

### 1. Actor dedicado

**`snipercoder~bulk-linkedin-email-finder`** — 2.456 usuarios, 99.7% de éxito, 4.86★.
Precio escalonado **$0.001→$0.0006/item** ($0.60–1.00 por 1.000) — el camino más barato.

```
linkedin_url_or_ids[]   # URL o slug pelado
csv_file                # CSV con columna de encabezado `linkedin_url_or_id`
```

### 2. Flag de modo en actores de perfil

El email no es un producto separado en el resto de la plataforma, es un modo:

| Actor | Cómo se pide |
|---|---|
| `harvestapi~linkedin-profile-scraper` | `profileScraperMode: "Profile details + email search ($10 per 1k)"` |
| `harvestapi~linkedin-company-employees` | `profileScraperMode: "Full + email search ($12 per 1k)"` |
| `harvestapi~linkedin-profile-search` | evento `full-profile-with-email` ($0.010→$0.008) |
| `harvestapi~linkedin-post-comments` | evento `full-profile-with-email` ($0.010) |
| `apimaestro~linkedin-profile-detail` | `includeEmail: true` |
| `dev_fusion~Linkedin-Profile-Scraper` | automático (`email`, `mobileNumber`) |

El modo con email cuesta aproximadamente **2,5× el modo sin email** en `harvestapi`.

## El email no se scrapea de LinkedIn

HarvestAPI es explícito: el email **no se extrae de LinkedIn** — se busca en fuentes externas y se valida por SMTP. Textualmente, *"not guaranteed to find an email for every profile"*, con facturación adaptativa (no cobra cuando el perfil es demasiado escueto para intentarlo).

**Consecuencias para el diseño del gem:**

1. **El email es siempre opcional, nunca garantizado.** No modelarlo como campo requerido ni asumir que un perfil enriquecido lo trae.
2. **No reintentar** un perfil sin email esperando que aparezca — no va a cambiar y cada intento cuesta.
3. **Reconciliar la tasa de hallazgo.** Si el gem cobra o reporta por email encontrado, exponer cuántos de N perfiles efectivamente lo trajeron.

## ⚠️ Implicancia legal — el Artículo 14 del GDPR

Esta es la exposición más ignorada del stack. Como el dato se recolecta de LinkedIn y no de la persona, hay que **notificar a cada sujeto dentro de un mes**. La exención de "esfuerzo desproporcionado" se interpreta de forma estrecha, y **si scrapeaste su email, generalmente se espera que lo uses para notificar**.

Es decir: **activar el modo de email crea un deber de notificación masiva**. Ningún actor provee plantilla de interés legítimo, mecanismo de notificación ni vía de DSAR — eso queda del lado del gem y de quien lo usa.

Ver [linkedin-compliance](../../linkedin-compliance/SKILL.md).

## Sin verificar

**El nombre del campo de email en el output de `harvestapi` y `apimaestro`.** No aparece en ningún README, página de store ni repo de GitHub consultado. Solo `dev_fusion` documenta explícitamente sus claves `email` y `mobileNumber`.

Tratar el email como passthrough opcional sin tipar hasta confirmarlo contra un run real con el modo activado.

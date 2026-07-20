---
name: apify-costs
description: Control de gasto en Apify para cargas de LinkedIn — por qué `maxItems` no protege a estos actores, qué hace `maxTotalChargeUsd`, los campos de tope propios de cada actor, y las trampas de facturación conocidas (evento no-result, mínimo de 150, dynamicFilterMatch, init_search).
when_to_use: Al agregar cualquier llamada que ejecute un actor, al estimar el costo de un scrape, al revisar por qué una factura de Apify salió más alta de lo esperado, o al implementar límites de gasto en el gem.
---

# Control de costos

## La trampa central: `maxItems` no protege a los actores de LinkedIn

Textual de la documentación de Apify:

> **`maxItems`** — "Specifies the maximum number of dataset items that will be charged for pay-per-result Actors. **This does NOT guarantee that the Actor will return only this many items.** It only ensures you won't be charged for more than this number." Se expone al actor como `ACTOR_MAX_PAID_DATASET_ITEMS`. **Solo funciona para actores pay-per-result.**

> **`maxTotalChargeUsd`** — "Specifies the maximum total cost of the run… **for all pricing models**." Se expone como `ACTOR_MAX_TOTAL_CHARGE_USD`.

Dos consecuencias:

1. **`maxItems` es un tope de facturación, no de resultados.** Para devolver como máximo N items hay que pasar *además* `limit=N` en la consulta al dataset.

2. **Casi todos los actores de LinkedIn son pay-per-_event_, no pay-per-_result_ — así que `maxItems` no los protege.** `maxTotalChargeUsd` es la única barrera universal.

**Regla para el gem: setear `maxTotalChargeUsd` por defecto en todo run, y además el campo de tope propio del actor.**

## Campos de tope por actor

Son desesperantemente inconsistentes. Mapa:

| Actor | Campo de tope |
|---|---|
| `harvestapi~linkedin-profile-search` | `maxItems` (⚠️ prefill 20, **sin default** → sin tope vía API) |
| `harvestapi~linkedin-company-search` | `maxItems` (máx 1000), `takePages` |
| `harvestapi~linkedin-company-employees` | `maxItems`, `maxItemsPerCompany`, `takePages` |
| `harvestapi~linkedin-profile-posts` | `maxPosts` (prefill 5; **0 = todos**) |
| `harvestapi~linkedin-post-search` | `maxPosts`, `scrapePages` |
| `apimaestro~*` | `limit`, `total_posts` |
| `valig~linkedin-jobs-scraper` | `limit` (default 100) |
| `curious_coder~linkedin-jobs-scraper` | `count` (prefill 100) |
| `cheap_scraper~linkedin-job-scraper` | `maxItems` |
| `bestscrapers~linkedin-sales-navigator-scraper` | `limit` (≤2500), `page` (≤25) |

> ⚠️ `maxPosts: 0` significa **todos los posts**, no cero. Un default mal puesto acá puede scrapear el historial completo de un perfil.

## Trampas de facturación conocidas

### 1. Evento `no-result` de `harvestapi` — $0.001 por run vacío
`harvestapi` cobra **aunque el run no devuelva nada**. Un loop de reintentos sobre resultados vacíos acumula costo en silencio.
**→ El gem no debe reintentar automáticamente runs vacíos de `harvestapi`.**

### 2. Mínimo de 150 resultados de `cheap_scraper` — facturables
`cheap_scraper~linkedin-job-scraper` factura un **mínimo de 150 resultados** sin importar cuántos devuelva. Una consulta chica sale desproporcionadamente cara.
**→ Para volumen bajo usar `valig~linkedin-jobs-scraper`.**

### 3. `dynamicFilterMatch` de `cheap_scraper` — marca pero no filtra
Varios filtros (`excludeRecruitingAgencies`, `companySizeMin/Max`, `requireSalaryInfo`, excludes de tipo de organización) **no filtran**: marcan la fila con `dynamicFilterMatch: false`, la recolectan igual **y la facturan**. Combinado con el mínimo de 150, una consulta muy filtrada puede costar mucho más de lo esperado.

### 4. `init_search` de Sales Navigator — $0.50 por búsqueda
`bestscrapers~linkedin-sales-navigator-scraper` cobra **$0.50 solo por iniciar** la búsqueda, antes de traer un solo lead. Los `fetch_results` son $0.01. Reintentar una búsqueda fallida cuesta otros $0.50.

### 5. Costos de arranque que se cobran igual si falla
`powerai~linkedin-peoples-search-scraper` cobra **$0.09 de arranque** y tiene **51.9% de éxito**. La mitad de esos arranques se pagan a cambio de nada. (Está en la lista de actores a evitar por esto.)

### 6. El modo con email cuesta ~2,5×
En `harvestapi`, `profile` = $0.004 vs `profile_with_email` = $0.010. Activar email en un scrape masivo por defecto multiplica la factura.

## Precios escalonados

Todos los precios de la base de conocimiento reflejan el tier **FREE/BRONZE**. Los tiers GOLD+ son **25–50% más baratos**. Las tablas muestran ambos extremos como `$X→$Y` (primero→último tier).

## Concurrencia vs memoria

**CU = (memoryMB / 1024) × horas** — la memoria es aproximadamente neutra en costo. Duplicar memoria a la mitad del tiempo cuesta lo mismo.

Por eso: **comprar velocidad con memoria, no con concurrencia.** La concurrencia es lo que ve la detección de comportamiento de LinkedIn, y además topa `concurrent-runs-limit-exceeded` (25 runs en plan Free).

Apify también recomienda **pocos runs grandes**: *"large runs can use full resource scaling and are not subjected to repeated Actor start-ups"*. Esto además amortiza el cargo de `actor-start` que cobran `harvestapi` y `cheap_scraper`.

## Reconciliación

`chargedEventCounts` y `usageTotalUsd` en el objeto Run son cómo se concilia el gasto **real** contra el estimado. Exponerlos como atributos de primera clase del resultado, no enterrarlos — en un modelo pay-per-event son la única forma de saber qué se pagó.

## Estado del gem

Ninguna de estas protecciones está implementada hoy. `Actors#run_sync_get_dataset_items` pasa el `input` tal cual, sin `maxTotalChargeUsd`, sin defaults de tope, sin reconciliación de `chargedEventCounts`.

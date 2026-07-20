---
name: apify-api
description: Mecánica de la API v2 de Apify tal como la necesita este gem — sync vs async, polling de runs, recuperación y paginación de datasets, webhooks, rate limits, catálogo de errores, y los parámetros memory/timeout/build.
when_to_use: Al implementar o modificar cualquier llamada HTTP del gem, al decidir entre ejecución sync y async, al agregar paginación o webhooks, al mapear un error nuevo de Apify a una excepción Ruby, o cuando un run da 408 / resultados vacíos / 429.
---

# API v2 de Apify

## Hallazgo crítico: el endpoint sync no alcanza para LinkedIn

El gem hoy usa `POST /v2/actors/{actorId}/run-sync-get-dataset-items`. La documentación es explícita:

> "**If the Actor run exceeds 300 seconds, the HTTP response will return the 408 status code (Request Timeout).**"
> "If the connection breaks, you will not receive any information about the run and its status."
> "To run the Actor asynchronously, use the Run Actor API endpoint instead."

Comparado contra el `timeoutSecs` **por defecto de cada actor de LinkedIn**:

| Actor | Timeout propio |
|---|---|
| `harvestapi~linkedin-company` | **30.000s** |
| `harvestapi~linkedin-profile-search` | **30.000s** |
| `harvestapi~linkedin-profile-scraper` | **18.000s** |
| `harvestapi~linkedin-company-employees` | **15.000s** |
| `apimaestro~*` | 3.600–10.800s |
| `dev_fusion~Linkedin-Profile-Scraper` | 3.000s |
| `cheap_scraper~linkedin-job-scraper` | 900s |
| `fantastic-jobs~advanced-linkedin-job-search-api` | 600s |
| `valig~linkedin-jobs-scraper` | 300s |

**El timeout propio de casi todo actor de LinkedIn excede el techo sync — la mayoría por 10–100×.** Solo `valig` (300s) y `fantastic-jobs` (600s) están cerca.

Un cliente solo-sync va a dar 408 en cualquier carga real de búsqueda de perfiles, empleados por empresa o perfiles en bulk. Y **al dar 408 se pierde el handle del run** mientras el run sigue ejecutando y facturando.

**Recomendación para el gem:** async + polling como default; sync como fast-path opt-in solo para lotes chicos, con el read timeout HTTP en ~310s para que emerja un 408 real en vez de un timeout de socket del lado cliente.

Detalle completo en [runs.md](references/runs.md).

## Convenciones base

- **Path:** usar **`/v2/actors/...`**. `/v2/acts/...` todavía responde 200 pero es legacy no documentado.
- **Auth:** header `Authorization: Bearer <token>` únicamente. La docs marca `?token=` como "less secure" porque las URLs quedan en historial y logs de servidor. El gem ya lo hace bien.
- **Spec máquina:** `https://docs.apify.com/api/openapi.json`
- **No existe cliente Ruby oficial.** Apify publica clientes para JS, Python, Java, Rust, .NET, PHP y Go. Ruby es el hueco que llena este gem.

## Referencias

| Tema | Documento |
|---|---|
| Runs sync/async, estados, polling, abort | [runs.md](references/runs.md) |
| Datasets, paginación, formatos, límites | [datasets.md](references/datasets.md) |
| Webhooks, reintentos, idempotencia | [webhooks.md](references/webhooks.md) |
| Catálogo de errores y mapeo a excepciones Ruby | [errors.md](references/errors.md) |
| Input schemas, `prefill` vs `default`, memory/timeout/build | [input-schemas.md](references/input-schemas.md) |

## Rate limits

- **Global:** 250.000 req/min (por usuario autenticado; por IP si no)
- **Default:** 60 req/s por recurso (un actor, run, dataset o KV store puntual)
- **200 req/s:** CRUD de registros de KV store
- **400 req/s:** **Run Actor**, run task async/sync, metamorph, push de items, CRUD de request queue

Cuerpo del 429:

```json
{"error": {"type": "rate-limit-exceeded", "message": "You have exceeded the rate limit of ... requests per second"}}
```

El límite del endpoint viene en **`X-RateLimit-Limit`**.

Backoff documentado: `DELAY = 500ms`; ante 429 esperar un período aleatorio en `[DELAY, 2*DELAY]`, duplicar `DELAY`, reintentar.

> ⚠️ **`Retry-After` no se menciona nunca en la documentación de Apify.** Calcular el backoff del lado cliente. El `RetryPolicy` actual del gem (backoff exponencial `retry_base_delay * 2^(n-1)`) es compatible con lo documentado; considerar agregar jitter para alinearse con el rango aleatorio que sugiere la docs.

## Estado del gem frente a esto

| Capacidad | Estado |
|---|---|
| Auth por header Bearer | ✅ Implementado |
| Sync `run-sync-get-dataset-items` | ✅ Implementado (`Client#post_sync_dataset_items`) |
| Errores tipados desde `error.type` | ✅ Implementado (`ErrorClassifier`) |
| Retry con backoff exponencial | ✅ Implementado (opt-in, `max_retries: 0`) |
| Runs async + polling | ❌ Falta — **es el gap más importante** |
| Paginación de datasets | ❌ Falta |
| Webhooks | ❌ Falta |
| `maxTotalChargeUsd` / control de costo | ❌ Falta — ver [apify-costs](../apify-costs/SKILL.md) |
| Validación de `memory` potencia de 2 | ❌ Falta |
| Reconciliación de resultados parciales | ❌ Falta |

`Client` está hardcodeado alrededor de un solo POST. Antes de sumar endpoints hay que generalizar `execute_post`/`post_request`/`handle_response` a un `request(method, path, ...)`.

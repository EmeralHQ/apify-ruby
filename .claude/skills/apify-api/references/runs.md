# Runs: sync y async

## Sync — `run-sync-get-dataset-items`

`POST /v2/actors/{actorId}/run-sync-get-dataset-items`
Docs: https://docs.apify.com/api/v2/act-run-sync-get-dataset-items-post

- **Éxito = 201**, no 200. (El gem hoy acepta el rango `200..299`, así que funciona, pero conviene saberlo.)
- Devuelve headers `X-Apify-Pagination-*`.
- Errores posibles: 400, 401, 402, 403, **408**.
- Acepta parámetros de control de run (`timeout`, `memory`, `maxItems`, `maxTotalChargeUsd`, `restartOnError`, `build`, `webhooks`) **y** el set completo de parámetros de formato de dataset.

### El problema del 408

> "If the Actor run exceeds 300 seconds, the HTTP response will return the 408 status code."
> "If the connection breaks, you will not receive any information about the run and its status."

Cuando esto pasa: **se pierde el handle del run, pero el run sigue corriendo y facturando.** No hay forma de recuperar el `runId` desde la respuesta fallida.

**Mitigación mínima si se mantiene el path sync:** registrar un webhook al arrancar el run (parámetro `webhooks`), así una conexión rota no pierde el run. Ver [webhooks.md](webhooks.md).

### `run-sync` a secas

`POST /v2/actors/{actorId}/run-sync` (sin `-get-dataset-items`) devuelve el registro `OUTPUT` del key-value store. La documentación lo llama *"a legacy approach"* y aclara que muchos actores nunca escriben `OUTPUT`. **No sirve para los actores de LinkedIn.**

## Async — el camino recomendado

### Arrancar

`POST /v2/actors/{actorId}/runs` → **201** + objeto Run

Parámetros: `timeout`, `memory`, `maxItems`, `maxTotalChargeUsd`, `restartOnError`, `build`, `waitForFinish` (**default 0, máx 60**), `webhooks`, `forcePermissionLevel`.

### Consultar

`GET /v2/actor-runs/{runId}` — único parámetro `waitForFinish`, **máx 60**.

Esto permite long-polling eficiente: hacer un loop de esperas de 60s en vez de dormir del lado cliente. Un run de perfiles de 20 minutos son ~20 requests, no 1.200.

### Estados

**No terminales:** `READY`, `RUNNING`, `TIMING-OUT`, `ABORTING`
**Terminales:** `SUCCEEDED`, `FAILED`, `TIMED-OUT`, `ABORTED`

> ⚠️ Ojo con los guiones: el estado del run es **`TIMED-OUT`** (guión) pero el evento de webhook es **`ACTOR.RUN.TIMED_OUT`** (guión bajo). Es una fuente fácil de bugs.

### Campos del objeto Run que el gem debería exponer

```
id, actId, status, statusMessage, isStatusMessageTerminal
startedAt, finishedAt
defaultDatasetId, defaultKeyValueStoreId
options   { build, timeoutSecs, memoryMbytes, maxItems, maxTotalChargeUsd }
stats     { durationMillis, computeUnits, memMaxBytes, ... }
chargedEventCounts {}
usage {}, usageTotalUsd, exitCode
```

> **`chargedEventCounts` y `usageTotalUsd` son cómo se concilia el gasto real** en los actores pay-per-event que dominan LinkedIn. Vale la pena exponerlos como atributos de primera clase en el resultado, no enterrarlos.

### Control de runs

- `POST /v2/actor-runs/{runId}/abort` — parámetro `gracefully` envía `aborting` + `persistState` y fuerza el corte a los 30s.
- `POST /v2/actor-runs/{runId}/resurrect` — ⚠️ el timeout cuenta desde la resurrección.
- `POST /v2/actor-runs/{runId}/metamorph`, `.../reboot`.

## `SUCCEEDED` no significa que los datos estén bien

Este es el modo de fallo más importante de toda la integración:

1. **Los resultados parciales son lo normal.** `dev_fusion` documenta que las URLs inválidas *"se saltan automáticamente con un warning"* y que *"los fallos de perfiles individuales no detienen el run completo"*. Un run puede terminar `SUCCEEDED` habiendo descartado la mayoría de los inputs.

2. **Los muros de autenticación y los challenges se ven como runs verdes con dataset vacío.** El `exitCode` no lo refleja.

3. **`harvestapi` emite `status` por item.** Filas con status distinto de 200 son registros de fallo.

**Lo que el gem debe hacer:**
- Reconciliar cantidad de filas devueltas contra cantidad de inputs enviados, y exponer la diferencia.
- Afirmar un rendimiento mínimo esperado; no confiar en el exit code.
- Separar filas de fallo (por `status`) de filas de datos.

## Sin verificar

- **No hay default ni máximo documentado de timeout de run.** Pasar `timeout` siempre de forma explícita.
- No hay tamaño máximo documentado de request/response para ningún endpoint. Lo único confirmado es **9 MB por item de dataset**.
- La cantidad de reintentos de los clientes oficiales ("8") sale del código fuente, no de la documentación.

# Diseño: runs asíncronos (start + poll) y paginación de datasets

> **Tipo**: documento de diseño (spike). No introduce código de producción.
> Entregable del Plan 009 (`plans/009-spike-async-paginacion.md`, issue
> [EmeralHQ/apify-ruby#10](https://github.com/EmeralHQ/apify-ruby/issues/10)).
> Los identificadores de código y los nombres de la API van en inglés; la
> prosa en español (convención del tracker del repo).
>
> **Estado del arte al escribir este diseño** (commit `09f910b`): el gem expone
> un único endpoint, `Apify.actors.run_sync_get_dataset_items`, implementado en
> `lib/apify/actors.rb` como passthrough hacia `Client#post_sync_dataset_items`
> (`lib/apify/client.rb:19-25`). `git diff --stat 09f910b..HEAD -- lib/` está
> vacío: el diseño parte de la base descrita en el plan.

## 1. Motivación (resumen)

El endpoint `run-sync-get-dataset-items` tiene tres límites estructurales,
todos visibles en el código actual:

1. **Techo de ~300s del lado de Apify**: los endpoints `run-sync-*` abortan con
   HTTP 408 `run-timeout-exceeded` (`spec/apify/actors_spec.rb:60` fixtura ese
   mensaje). Actores lentos o con input grande son inutilizables.
2. **Conexión HTTP bloqueada hasta 310s** (`read_timeout` default 310,
   `lib/apify/config.rb:12`): cada run ocupa un thread + una conexión durante
   minutos en un worker Sidekiq/Puma.
3. **Dataset completo en RAM**: `parse_success_body` hace `JSON.parse` del body
   entero (`lib/apify/client.rb:71-80`), sin `limit`/`offset`.

La vía asíncrona de la API v2 resuelve los tres: iniciar el run (retorno
inmediato), consultar estado con polling barato, y leer items paginados en
lotes acotados.

---

## 2. Contrato de la API (verificado contra https://docs.apify.com/api/v2)

Fuentes consultadas el 2026-07-20: `act-runs-post`, `actor-run-get`,
`dataset-items-get`. La documentación **confirma el diseño de 3 endpoints**
asumido en el plan; no hay contradicción (no se dispara la condición de STOP).

### 2.1. Iniciar un run (asíncrono)

```
POST https://api.apify.com/v2/acts/:actorId/runs
```

> Nota: la doc usa tanto `/v2/acts/...` como `/v2/actors/...`; ambas rutan al
> mismo recurso. El gem ya usa el segmento `actors` en la ruta sync
> (`lib/apify/client.rb:20`), así que se recomienda mantener `actors` por
> coherencia interna.

- **Path param**: `actorId` — ID (`vKg4IjxZbEYTYeW8T`) o `username~actor-name`.
- **Query params relevantes**: `build`, `timeout` (segundos, timeout del run en
  Apify), `memory` (MB, potencia de 2, min 128), `maxItems`,
  `maxTotalChargeUsd`, `webhooks` (JSON base64), `waitForFinish` (0-60s, default
  0 — el servidor espera hasta N segundos antes de responder; **no** lo usamos
  para bloquear, hacemos polling desde el cliente).
- **Body**: el JSON se pasa como `INPUT` al actor (`Content-Type:
  application/json`). Es exactamente el mismo payload que hoy manda el gem.
- **Respuesta `201`**: objeto `Run` bajo la clave `data`. Campos clave:
  - `id` — run id (se usa para el polling).
  - `actId`, `userId`.
  - `status` — estado inicial (típicamente `READY`).
  - `startedAt`, `finishedAt` (null mientras corre).
  - `defaultDatasetId` — **dataset donde aparecerán los resultados** (se usa
    para la paginación).
  - `defaultKeyValueStoreId`, `defaultRequestQueueId`.

### 2.2. Consultar estado de un run

```
GET https://api.apify.com/v2/actor-runs/:runId
```

- **Path param**: `runId`.
- **Auth**: el propio `runId` es difícil de adivinar; el endpoint no exige
  token. Aun así mandamos `Authorization: Bearer ...` (necesario para ver
  campos de coste y consistente con el resto del cliente).
- **Respuesta `200`**: objeto `Run` bajo `data`, misma forma que 2.1
  (`id`, `status`, `defaultDatasetId`, `startedAt`, `finishedAt`, `stats`,
  `usage`, `usageTotalUsd`).
- **Estados** (`status`):
  - Transitorios: `READY`, `RUNNING`, `TIMING-OUT`, `ABORTING`.
  - **Terminales**: `SUCCEEDED`, `FAILED`, `TIMED-OUT`, `ABORTED`.

  El polling sigue hasta un estado terminal. Solo `SUCCEEDED` es éxito; el resto
  de terminales son error (ver decisión D3).

### 2.3. Leer items del dataset (paginado)

```
GET https://api.apify.com/v2/datasets/:datasetId/items?offset=&limit=
```

- **Path param**: `datasetId` (= `defaultDatasetId` del run).
- **Query params relevantes**: `offset` (default 0), `limit` (**sin default —
  si se omite devuelve todo**, justo lo que queremos evitar), `fields`, `omit`,
  `clean`, `skipHidden`, `skipEmpty`, `desc`, `format` (default `json`).
- **Respuesta `200`**: un array JSON de items (con `format=json`, que es el
  default y el único que nos interesa). Los metadatos de paginación **vienen en
  headers**, no en el body:
  - `X-Apify-Pagination-Offset`
  - `X-Apify-Pagination-Limit`
  - `X-Apify-Pagination-Count` — items en esta página.
  - `X-Apify-Pagination-Total` — total de items en el dataset.

  > Contraste con `run-sync-get-dataset-items`, que también devuelve un array
  > JSON directo — o sea `parse_success_body` (que exige `Array`,
  > `lib/apify/client.rb:75`) es reutilizable tal cual para cada página.

- **Condición de fin de paginación**: parar cuando `offset + count >= total`
  (usando el header `Total`), o de forma defensiva cuando `count == 0` o
  `count < page_size`. Preferir el header `Total` por robustez.

---

## 3. Superficie propuesta del gem

Tres piezas: `Actors#start`, `Actors#wait_for_finish` y un nuevo `Datasets`
con streaming. Coherentes con el estilo actual (kwargs, "raw Apify responses").

### 3.1. Firmas

```ruby
module Apify
  class Actors
    # Inicia el run y retorna de inmediato. Devuelve el objeto Run (Hash "data").
    # POST /actors/:actor_id/runs
    def start(actor_id:, input:, build: nil, timeout: nil, memory: nil, max_items: nil)
    end

    # Hace polling de GET /actor-runs/:run_id con backoff hasta estado terminal.
    # Devuelve el Run terminal. Lanza RunFailedError si el estado != SUCCEEDED.
    # `timeout`: tope total de espera en segundos (nil = sin tope del lado cliente).
    def wait_for_finish(run_id:, timeout: nil)
    end

    # Azúcar: start + wait_for_finish + paginar el defaultDatasetId completo.
    # Reemplazo async de run_sync_get_dataset_items sin el techo de 300s.
    # (Materializa todo el dataset en memoria — documentar el trade-off.)
    def run_get_dataset_items(actor_id:, input:, timeout: nil, page_size: 1_000)
    end
  end

  class Datasets
    # Itera el dataset en lotes de `page_size`. Hace yield de cada lote (Array).
    # Sin bloque, devuelve un Enumerator (lazy).
    # GET /datasets/:dataset_id/items?offset=&limit=
    def each_items(dataset_id:, page_size: 1_000, fields: nil, clean: false)
    end
  end
end
```

Puntos de entrada, consistentes con `Apify.actors` (memoizado en el módulo
`Apify`):

```ruby
Apify.actors      # => Apify::Actors  (ya existe)
Apify.datasets    # => Apify::Datasets  (nuevo, mismo patrón de memoización)
```

### 3.2. Ejemplo de uso end-to-end

```ruby
# 1) Iniciar (no bloquea; retorna en ~1 request)
run = Apify.actors.start(
  actor_id: "dev_fusion~linkedin-profile-scraper",
  input: { profileUrls: ["https://www.linkedin.com/in/williamhgates"] }
)
run["id"]                 # => "abc123"
run["status"]             # => "READY"
run["defaultDatasetId"]   # => "DS456"

# 2) Esperar a que termine (polling con backoff; sin ocupar la conexión)
finished = Apify.actors.wait_for_finish(run_id: run["id"], timeout: 3_600)
finished["status"]        # => "SUCCEEDED"  (o RunFailedError)

# 3) Leer resultados en lotes acotados (nunca todo el dataset en RAM)
Apify.datasets.each_items(dataset_id: finished["defaultDatasetId"], page_size: 1_000) do |batch|
  batch.each { |profile| process(profile) }
end

# Atajo equivalente al endpoint sync de hoy, pero sin el techo de 300s:
items = Apify.actors.run_get_dataset_items(
  actor_id: "dev_fusion~linkedin-profile-scraper",
  input: { profileUrls: [...] },
  timeout: 3_600
)
```

---

## 4. Decisiones de diseño (con recomendación)

### D1. ¿`Run` como value object o Hash crudo?

Hoy el gem devuelve "raw Apify responses" (arrays/hashes de `JSON.parse`, ver
`parse_success_body`). Introducir un `Run` value object rompería esa coherencia
y obligaría a mapear cada campo.

**Recomendación**: **Hash crudo** (el objeto `data` tal cual). Mantiene la
convención existente y el acoplamiento mínimo con el shape de Apify. Encapsular
solo lo imprescindible con helpers privados o constantes (p.ej. el set de
estados terminales) dentro de `Actors`, sin exponer una clase pública. Si más
adelante hace falta ergonomía, un `Run` wrapper es aditivo y no-breaking.

### D2. ¿El polling reutiliza `RetryPolicy` o una `PollingPolicy` propia?

`RetryPolicy` (`lib/apify/retry_policy.rb`) reintenta **solo** ante
`TransientError` y con `max_retries` default 0 — está pensada para reintentar
*fallos*, no para *sondear un estado que aún no es terminal*. Son semánticas
distintas:

- `RetryPolicy`: "el request falló de forma transitoria, reintenta".
- Polling: "el request tuvo éxito (200) pero `status` sigue `RUNNING`, espera y
  vuelve a preguntar".

**Recomendación**: **`PollingPolicy` nueva y separada**, que reutilice las
mismas primitivas de config para no martillar la API (Plan 005):
`config.sleep_fn` (inyectable — clave para tests, ver `spec/spec_helper.rb:18`),
backoff exponencial con **tope máximo** (p.ej. crecer 1s→2s→4s→…→cap 30s) y
**jitter**. Cada request individual del poll **sí** pasa por `RetryPolicy`
(un 503 al pollear debe reintentarse). O sea: `PollingPolicy` envuelve un bucle;
dentro del bucle, `Client` sigue usando `RetryPolicy`. Config nueva sugerida:
`poll_interval` (base, default 2s), `poll_max_interval` (cap, default 30s),
`poll_timeout` (tope total, default nil).

### D3. ¿Qué errores nuevos hacen falta?

La jerarquía actual (`lib/apify/error.rb`) cubre errores HTTP, no el caso "el
run terminó pero no con éxito". Falta:

- **`RunFailedError < ApiError`** — cuando `wait_for_finish` llega a un estado
  terminal `FAILED`/`TIMED-OUT`/`ABORTED`. Debe llevar `run_id`, `status` y
  (si aplica) `defaultDatasetId` para diagnóstico. `code: "run_failed"`.
- **`PollTimeoutError < ApiError`** (opcional) — cuando se supera `poll_timeout`
  del lado cliente sin alcanzar estado terminal. `code: "poll_timeout"`.
  Alternativa: reutilizar el `TimeoutError` existente (`code: "timeout_error"`),
  pero semánticamente aquí no hubo timeout HTTP sino agotamiento del polling.

**Recomendación**: añadir `RunFailedError` (imprescindible) y `PollTimeoutError`
(recomendado, por claridad de diagnóstico). Ambos `< ApiError`, `retryable?`
false. Nota: por consistencia con Apify, cuando `status == "TIMED-OUT"` el
`RunFailedError` puede exponer eso en su `status`, distinto del timeout de
polling del cliente.

### D4. ¿`run_sync_get_dataset_items` queda como azúcar o intacto?

Cambiar su implementación por debajo (sync → async) alteraría su latencia,
su manejo de errores (408 vs polling) y su semántica observable. Es un cambio
breaking encubierto.

**Recomendación**: **dejar `run_sync_get_dataset_items` intacto** (sigue
llamando al endpoint sync, con su techo de 300s documentado). La vía async es
**aditiva** vía `start` / `wait_for_finish` / `each_items` +
`run_get_dataset_items` como atajo. Los usuarios eligen: sync para runs cortos
(1 request, menos código), async para runs largos / datasets grandes. Documentar
claramente cuándo usar cada uno.

### D5. Encoding de path params (Plan 002)

`run_id` y `dataset_id` son nuevos path params. Deben validarse/encodearse
igual que `actor_id` según el Plan 002 (evitar inyección de path / caracteres
`~`, `/`). Registrar como requisito de la implementación.

### D6. Paginación: ¿cómo detectar el fin?

**Recomendación**: leer `X-Apify-Pagination-Total` y `-Count` de los headers y
parar cuando `offset + count >= total`. Fallback defensivo: parar si `count == 0`.
Esto exige que `Client` exponga los **headers** de la respuesta paginada, no
solo el body parseado (hoy `handle_response` descarta el objeto response tras
parsear el body — habrá que devolver `{ items:, headers: }` en el método nuevo,
sin tocar el método sync existente).

---

## 5. Prototipo (start → poll → paginate contra WebMock)

Prototipo **descartable** — pseudocódigo ejecutable que demuestra el flujo con
stubs WebMock, en el estilo de `spec/support/apify_helpers.rb`. No se añade a
`spec/` (nada activo en el repo); sirve como guía de la implementación y de sus
tests. Verificado que el patrón de stub calza con `spec_helper.rb` (inyección de
`sleep_fn` para no dormir en tests, `Apify.reset!` entre ejemplos).

```ruby
# frozen_string_literal: true
#
# PROTOTIPO DESCARTABLE — no forma parte de la suite. Documenta el contrato.
RSpec.describe "async run flow (prototype)", skip: "spike/prototype only" do
  API = "https://api.apify.com/v2"
  ACTOR = "dev_fusion~linkedin-profile-scraper"

  before do
    Apify.reset!
    Apify.configure do |c|
      c.api_token = "test-apify-token"
      c.sleep_fn = ->(_s) {}   # no dormir durante el poll en tests
    end
  end

  it "start -> poll -> paginate" do
    auth = { "Authorization" => "Bearer test-apify-token" }

    # 1) start: POST /actors/:id/runs -> 201 con Run inicial
    stub_request(:post, "#{API}/actors/#{ACTOR}/runs")
      .with(headers: auth, body: { profileUrls: ["u"] }.to_json)
      .to_return(
        status: 201,
        body: { data: { id: "R1", status: "READY", defaultDatasetId: "DS1" } }.to_json
      )

    # 2) poll: GET /actor-runs/R1 -> RUNNING, luego SUCCEEDED
    stub_request(:get, "#{API}/actor-runs/R1")
      .with(headers: auth)
      .to_return(
        { status: 200, body: { data: { id: "R1", status: "RUNNING",   defaultDatasetId: "DS1" } }.to_json },
        { status: 200, body: { data: { id: "R1", status: "SUCCEEDED", defaultDatasetId: "DS1" } }.to_json }
      )

    # 3) paginate: GET /datasets/DS1/items?offset=&limit= -> dos páginas
    stub_request(:get, "#{API}/datasets/DS1/items")
      .with(headers: auth, query: { offset: "0", limit: "2" })
      .to_return(
        status: 200,
        body: [{ n: 1 }, { n: 2 }].to_json,
        headers: {
          "X-Apify-Pagination-Offset" => "0", "X-Apify-Pagination-Limit" => "2",
          "X-Apify-Pagination-Count" => "2", "X-Apify-Pagination-Total" => "3"
        }
      )
    stub_request(:get, "#{API}/datasets/DS1/items")
      .with(headers: auth, query: { offset: "2", limit: "2" })
      .to_return(
        status: 200,
        body: [{ n: 3 }].to_json,
        headers: {
          "X-Apify-Pagination-Offset" => "2", "X-Apify-Pagination-Limit" => "2",
          "X-Apify-Pagination-Count" => "1", "X-Apify-Pagination-Total" => "3"
        }
      )

    run = Apify.actors.start(actor_id: ACTOR, input: { profileUrls: ["u"] })
    finished = Apify.actors.wait_for_finish(run_id: run["id"], timeout: 60)
    expect(finished["status"]).to eq("SUCCEEDED")

    all = []
    Apify.datasets.each_items(dataset_id: finished["defaultDatasetId"], page_size: 2) do |batch|
      all.concat(batch)
    end
    expect(all).to eq([{ "n" => 1 }, { "n" => 2 }, { "n" => 3 }])
  end

  it "raises RunFailedError on terminal FAILED" do
    stub_request(:get, "#{API}/actor-runs/R2")
      .to_return(status: 200, body: { data: { id: "R2", status: "FAILED" } }.to_json)
    expect { Apify.actors.wait_for_finish(run_id: "R2") }
      .to raise_error(Apify::RunFailedError)
  end
end
```

Pseudocódigo de la lógica de paginación (para `Datasets#each_items`):

```
offset = 0
loop do
  resp = client.get_dataset_items(dataset_id, offset: offset, limit: page_size, ...)
  items = resp[:items]          # Array (parse_success_body reutilizado)
  break if items.empty?
  yield items
  total = resp[:headers]["x-apify-pagination-total"].to_i
  count = resp[:headers]["x-apify-pagination-count"].to_i
  offset += count
  break if offset >= total
end
```

---

## 6. Estimación de esfuerzo (implementación real)

| Componente | Esfuerzo | Notas |
|-----------|----------|-------|
| `Client#post_run` (POST /actors/:id/runs) | **S** | Casi idéntico a `post_sync_dataset_items`; distinto path y parsea `data` (Hash) en vez de Array. Requiere un `parse_object_body` hermano de `parse_success_body`. |
| `Client#get_run` (GET /actor-runs/:id) | **S** | GET nuevo (hoy el cliente solo hace POST). Reutiliza `handle_response` + `RetryPolicy`. |
| `Client#get_dataset_items` (GET paginado + headers) | **M** | GET con query params; debe devolver `{ items:, headers: }` (exponer headers es nuevo). Encoding de `dataset_id` (Plan 002). |
| `PollingPolicy` (backoff+cap+jitter+timeout) | **M** | Nueva clase + settings de config (`poll_interval`, `poll_max_interval`, `poll_timeout`). Tests con `sleep_fn` inyectado. |
| `Actors#start` / `#wait_for_finish` / `#run_get_dataset_items` | **M** | Orquestación; set de estados terminales; mapeo a `RunFailedError`. |
| `Datasets#each_items` + `Apify.datasets` | **M** | Streaming + Enumerator lazy sin bloque; loop de paginación. |
| Errores `RunFailedError` / `PollTimeoutError` | **S** | Aditivo sobre `lib/apify/error.rb`. |
| Encoding path params (`run_id`, `dataset_id`) | **S** | Aplicar utilidad del Plan 002. |
| Suite de specs (WebMock) para todo lo anterior | **M** | Cubrir feliz + FAILED/ABORTED/TIMED-OUT + timeout de poll + multipágina + fin por header. |

**Total estimado**: **L** (coincide con el `Effort: L` del plan). Ninguna pieza
es individualmente grande; el volumen viene de sumar varios componentes M + su
cobertura de tests.

---

## 7. Preguntas abiertas para el maintainer

1. **Ruta `acts` vs `actors`**: la doc usa ambas. ¿Fijamos `actors` por
   coherencia con la ruta sync existente? (recomendación: sí).
2. **`Apify.datasets` como namespace nuevo**: ¿ok introducir un segundo punto de
   entrada además de `Apify.actors`, o preferís que la paginación cuelgue de
   `Apify.actors` / de un objeto `run`?
3. **Defaults de polling**: ¿`poll_interval` 2s, cap 30s, `poll_timeout` nil
   (sin tope de cliente) son razonables para el perfil de uso? ¿O querés un tope
   de cliente por defecto para evitar polling infinito ante un run colgado?
4. **`page_size` default 1000**: ¿valor sensato? Apify no impone default de
   `limit`; conviene uno explícito para no traer todo. ¿Ajustar según tamaño
   típico de item?
5. **`RunFailedError` vs retorno del Run**: ¿lanzar excepción en terminal no-
   `SUCCEEDED` (recomendado) o devolver el Run y dejar que el caller inspeccione
   `status`? Afecta ergonomía.
6. **`waitForFinish` server-side (0-60s)**: ¿lo usamos como primer intento
   barato antes de entrar al bucle de polling (ahorra un round-trip para runs
   muy rápidos), o mantenemos el polling puro por simplicidad?
7. **Webhooks**: la API soporta `webhooks` en el POST. ¿Fuera de alcance para
   esta iteración (nota del Plan 007 sobre no-objetivos)? Recomendación: sí,
   fuera de alcance; documentar como vía futura alternativa al polling.

## 8. Issues nuevos a abrir (derivados de este entregable)

- **#N — feat: `Actors#start` + `Client#post_run`** (POST async, parse de `data`).
- **#N — feat: `Actors#wait_for_finish` + `PollingPolicy`** (polling con
  backoff/cap/jitter/timeout; `RunFailedError` / `PollTimeoutError`).
- **#N — feat: `Datasets#each_items` + `Client#get_dataset_items`** (paginación
  por header, streaming, `Apify.datasets`).
- **#N — feat: `Actors#run_get_dataset_items`** (atajo async; sustituto sin
  techo de 300s del endpoint sync).
- **#N — chore: encoding/validación de `run_id` y `dataset_id`** (aplicar Plan
  002 a los nuevos path params).

Sugerencia de orden: los cuatro primeros son secuenciales por dependencia
(`start` → `wait_for_finish` → `each_items` → atajo); el de encoding es
transversal y debería aterrizar junto al primer path param nuevo.

## 9. No-objetivos (registro explícito)

- **Keep-alive / connection pooling** (nota del Plan 007): con la conexión ya no
  bloqueada 300s+, el pooling pierde urgencia. Mantener como no-objetivo salvo
  evidencia de volumen que lo justifique.
- **Webhooks** como mecanismo de notificación de fin de run: alternativa válida
  al polling, pero fuera del alcance de esta iteración (ver pregunta 7).
- **Reescribir `run_sync_get_dataset_items`** sobre la vía async (ver D4): se
  mantiene intacto.

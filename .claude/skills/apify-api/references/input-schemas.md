# Input schemas, memory, timeout y build

## Spec de input schema

https://docs.apify.com/platform/actors/development/actor-definition/input-schema/specification/v1

Raíz: `type: "object"`, `schemaVersion: 1`, `title`, `description`, `properties`, `required[]`, `additionalProperties` (default `true`).

Tipos: `string`, `boolean`, `integer`, `number`, `array`, `object`.

Valores de `editor`:

| Tipo | Editores |
|---|---|
| string | `textfield, textarea, javascript, python, select, datepicker, fileupload, hidden` |
| boolean | `checkbox, hidden` |
| integer / number | `number, hidden` |
| object | `json, proxy, schemaBased, hidden` |
| array | `json, requestListSources, pseudoUrls, globs, keyValue, stringList, fileupload, select, schemaBased, hidden` |

Tope de tamaño del schema: 500 kB.

## ⚠️ `prefill` vs `default` — lo más importante de este documento

| | Efecto |
|---|---|
| **`prefill`** | Solo prepobla la **UI de la Consola**. **Ningún efecto vía API.** |
| **`default`** | Se aplica del lado servidor cuando se omite el valor, **incluido vía API**. |

Esto muerde fuerte con los actores de LinkedIn:

- **`harvestapi~linkedin-profile-scraper`** define `profileScraperMode` como **prefill sin default**. Un llamador por API que lo omita obtiene un modo *indefinido*, no el modo barato de $4/1k.
- **`harvestapi~linkedin-profile-search`** tiene `maxItems` como **prefill 20 sin default**. Omitirlo vía API significa **sin tope de resultados** — y con `search-page` a $0.10 eso escala rápido.

**Regla para el gem: aplicar los prefills como defaults del lado cliente en todo campo sensible a costo.** No asumir que omitir un campo equivale a su valor mostrado en la Consola.

## Descubrir schemas en runtime

Ambos endpoints son **públicos, sin autenticación**:

```bash
# metadata del actor → taggedBuilds.latest.buildId
curl -s https://api.apify.com/v2/acts/harvestapi~linkedin-profile-scraper | jq '.data'

# schema de input real
curl -s https://api.apify.com/v2/acts/harvestapi~linkedin-profile-scraper/builds/<buildId> \
  | jq '.data.actorDefinition.input'
```

`actorDefinition.readme` trae además ejemplos de output.

**Decisión de arquitectura sugerida:** dado que casi todos estos actores se modificaron en los últimos 30 días, el gem puede **obtener y validar schemas en tiempo de codegen** en vez de mantener copias a mano que se desactualizan. Es probablemente la decisión de diseño de mayor valor disponible acá.

## Memory

- **128–32768 MB, debe ser potencia de 2.** Validar del lado cliente antes de mandar el request.
- CPU: un core completo por cada 4096 MB (512 MB = ⅛ core, 8192 MB = 2 cores).
- **CU = (memoryMB / 1024) × horas.** Se reporta por run en `stats.computeUnits`.

> **La memoria es aproximadamente neutra en costo:** `Memory × Duración = CU`. Duplicar la memoria a la mitad del tiempo cuesta lo mismo. Conviene **comprar velocidad con memoria, no con concurrencia** — la concurrencia es lo que ve la detección de comportamiento de LinkedIn. Apify incluso señala que se puede *bajar* la memoria para reducir presión sobre el sitio objetivo.

## Límites por plan

| Límite | Valor |
|---|---|
| Memoria de build | 4096 MB |
| Memoria por run | 16384 MB (Free/Starter) |
| Memoria combinada | 16384 MB (Free) → 524288 MB (Business) |
| Runs concurrentes | **25 (Free) → 256 (Business)** |
| Máx. caracteres de log | 10.485.760 |
| Máx. metamorphs | 10 |

> El límite de runs concurrentes es el que produce `concurrent-runs-limit-exceeded`. En plan Free, 25 se topa fácil si el gem paraleliza. Ver [errors.md](errors.md).

## `build`

Acepta un **tag o número de build** (`latest`, `beta`, `0.1.234`) — documentado como tag-o-número, **no** como build ID.

Fijar un build da reproducibilidad, pero estos actores cambian seguido: fijar `latest` implica aceptar cambios de schema, y fijar una versión implica quedarse atrás cuando LinkedIn cambia y el actor se adapta. Para LinkedIn conviene **`latest` con validación de schema**, no pinning.

## Sin verificar

- **No hay default ni máximo documentado de timeout de run.** Pasar `timeout` siempre explícito.
- No hay tamaño máximo documentado de payload de request/response.

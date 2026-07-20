# Búsqueda de personas (estilo Sales Navigator)

## Actores

| Actor ID | Usuarios | Éxito | Precio |
|---|---|---|---|
| `harvestapi~linkedin-profile-search` | 29.852 | 99.2% | `search-page` **$0.10→$0.05**, `full-profile` $0.004→$0.0032, `full-profile-with-email` $0.010→$0.008 |
| `harvestapi~linkedin-profile-search-by-name` | 5.099 | 98.4% | ídem |
| ~~`powerai~linkedin-peoples-search-scraper`~~ | 3.661 | **51.9%** ❌ | arranque **$0.09** + $0.00999/item |
| `bestscrapers~linkedin-sales-navigator-scraper` | 2.448 | 99.4% | arranque $0.0001 + **`init_search` $0.50** + `fetch_results` $0.01 |

> ❌ `powerai~linkedin-peoples-search-scraper`: 51.9% de éxito, 1.0★, y cobra los $0.09 de arranque igual cuando falla.

## `harvestapi~linkedin-profile-search` — el actor insignia

~40 campos de filtro:

```
searchQuery
locations[], currentCompanies[], pastCompanies[], schools[]
currentJobTitles[], pastJobTitles[]
seniorityLevelIds[], functionIds[], industryIds[]
firstNames[], lastNames[], profileLanguages[]
companyHeadcount[], companyHeadquarterLocations[]
recentlyChangedJobs, recentlyPostedOnLinkedIn
# set paralelo completo de exclude*
startPage, takePages
```

> ⚠️ `maxItems` es **prefill 20 sin default** — omitirlo vía API significa **sin tope de resultados**. Aplicarlo siempre explícitamente desde el gem.

### Segmentación automática de consultas

```
autoQuerySegmentation                 : bool
autoQuerySegmentationLevels[]
autoQuerySegmentationTargetCountries[]
```

Divide una consulta amplia en sub-consultas para superar el techo de resultados por búsqueda de LinkedIn. **Esta es la forma correcta de conseguir volumen** — LinkedIn pagina perfiles de a 25 y topea el total por búsqueda; subir `limit` no lo sortea, segmentar sí.

### ⚠️ Dedup con MongoDB — no usar desde el gem

```
profileDeduplicationMode : off | insert_ids | insert_profiles | read_only
mongoDbConnectionString
mongoDbDatabaseName
postFilteringMongoDbQuery
postFilteringMongoDbAggregation
```

Esto implica **pasar un connection string de una base viva como input del actor** — queda almacenado en el registro de input del run, visible en la Consola de Apify y en la API.

**El gem debe hacer la deduplicación del lado cliente.** No exponer estos campos.

## `bestscrapers~linkedin-sales-navigator-scraper` — protocolo de dos fases

Requiere un protocolo asíncrono propio que el gem tendría que modelar explícitamente:

1. Llamada inicial con `sales_url` + `limit` (≤2500) → se factura **$0.50 (`init_search`)** y devuelve un `request_id`.
2. Polling con `request_id` + `page` (≤25, 100 leads por página) → se factura $0.01 por `fetch_results`.

Requiere una **URL de Sales Navigator**, lo que implica un asiento pago de Sales Navigator del lado del usuario. Dado el costo de arranque y el protocolo particular, tratarlo como capacidad opcional de segunda fase, no del núcleo del gem.

## Caps estructurales de LinkedIn

| Superficie | Cap |
|---|---|
| Búsqueda de personas | 25 perfiles/página, techo total por búsqueda |
| Búsqueda de empresas | **página 20** máximo (50/página) |
| Búsqueda de empleos | ~1000 empleos por URL de búsqueda |
| Empleados por empresa | 25 perfiles/página, `takePages` 0..100 |

Las consultas amplias necesitan **segmentación, no límites más altos**.

# Datasets: recuperación y paginación

## Endpoints

```
GET /v2/datasets/{datasetId}/items
GET /v2/actor-runs/{runId}/dataset/items      # mismos parámetros
```

El segundo evita tener que guardar el `defaultDatasetId` por separado — con el `runId` alcanza.

## Parámetros

| Grupo | Parámetros |
|---|---|
| Formato | `format` (`json` default; `jsonl, csv, html, xlsx, xml, rss`) |
| Paginación | `offset` (0), `limit` (**sin default**), `desc` |
| Selección de campos | `fields`, `outputFields`, `omit`, `unwind`, `flatten` |
| Limpieza | `clean`, `skipHidden`, `skipEmpty`, `skipFailedPages`, `simplified`, `view` |
| Tabular | `delimiter`, `bom`, `xmlRoot`, `xmlRow`, `skipHeaderRow` |
| Otros | `attachment`, `feedTitle`, `feedDescription`, `signature` |

## Headers de paginación

```
X-Apify-Pagination-Offset
X-Apify-Pagination-Limit
X-Apify-Pagination-Count
X-Apify-Pagination-Total
```

## ⚠️ La trampa de paginación

Con `clean`, `skipEmpty`, `skipHidden` o `skipFailedPages` activos, la documentación advierte que *"los resultados pueden contener menos items que el valor de `limit`"*.

**Por lo tanto: `count < limit` NO significa fin de datos.**

El patrón ingenuo `while items.size == limit` termina la paginación antes de tiempo y pierde datos en silencio — exactamente el tipo de bug que no da error y aparece semanas después como "faltan perfiles".

**Paginar contra `X-Apify-Pagination-Total` y `offset`**, no contra la cantidad devuelta:

```ruby
offset = 0
loop do
  page = fetch(offset: offset, limit: 1000)
  break if page.items.empty?
  yield page.items
  offset += 1000                      # avanzar por limit, no por items.size
  break if offset >= page.total       # total viene del header
end
```

## Límites

| Límite | Valor |
|---|---|
| Tamaño por item | **9 MB** |
| Columnas en formatos tabulares | 2.000 |
| Expiración de datasets sin nombre | **7 días** |

> Los 9 MB por item son la razón por la que hay que dejar `postNestedComments` y `postNestedReactions` en `false` en los actores de posts — anidar cientos de reacciones puede reventar el límite. Ver [posts.md](../../linkedin-actors/references/posts.md).

> La expiración a 7 días importa si el gem guarda un `datasetId` para leerlo después. Para runs con nombre no aplica, pero el default de un run de actor es un dataset sin nombre.

## Formato para volumen

Para datasets grandes, `format=jsonl` permite parseo en streaming línea por línea en vez de cargar un array JSON completo en memoria.

El gem hoy hace `JSON.parse(body)` sobre la respuesta entera y exige que sea un Array (`Client#parse_success_body`). Para búsquedas de perfiles o empleados por empresa —donde el volumen es alto— conviene una ruta de streaming con `jsonl`.

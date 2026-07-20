# Base de conocimiento — apify-ruby

Este gem es **exclusivamente LinkedIn**. Estas skills son la documentación de apoyo del dominio: qué actores existen, cómo se comporta la API de Apify bajo estas cargas, cuánto cuesta y qué restricciones legales aplican.

| Skill | Para qué |
|---|---|
| [linkedin-actors](linkedin-actors/SKILL.md) | Catálogo de actores: cuál usar para cada capacidad, actor IDs, schemas de input, forma del output, precios, cuáles evitar |
| [apify-api](apify-api/SKILL.md) | Mecánica de la API v2: sync vs async, runs, datasets, webhooks, errores, memory/timeout/build |
| [apify-costs](apify-costs/SKILL.md) | Control de gasto y trampas de facturación |
| [linkedin-compliance](linkedin-compliance/SKILL.md) | GDPR, ToS de LinkedIn, jurisprudencia |

## Los tres hallazgos que más condicionan el diseño del gem

1. **El endpoint sync no alcanza.** El timeout propio de casi todo actor de LinkedIn (15.000–30.000s en `harvestapi`) excede el techo de 300s de `run-sync-get-dataset-items` por 10–100×. Un cliente solo-sync va a dar 408 en cualquier carga real, **y al dar 408 se pierde el handle del run mientras sigue facturando**. Async + polling debería ser el default. → [apify-api](apify-api/SKILL.md)

2. **`maxItems` no protege.** Es un tope de facturación solo para actores pay-per-*result*, y casi todos los de LinkedIn son pay-per-*event*. `maxTotalChargeUsd` es la única barrera universal. → [apify-costs](apify-costs/SKILL.md)

3. **`SUCCEEDED` no significa datos correctos.** Los resultados parciales son lo normal: las URLs inválidas se descartan en silencio y los muros de auth se ven como runs verdes con dataset vacío. **Reconciliar filas devueltas contra inputs enviados es probablemente el feature de seguridad más valioso que puede tener el gem.** → [apify-api](apify-api/SKILL.md)

## Procedencia

Los datos de actores (IDs, precios, estadísticas, schemas) se extrajeron en vivo de la API pública de Apify, no de memoria:

```bash
curl -s https://api.apify.com/v2/acts/{username}~{name}
curl -s https://api.apify.com/v2/acts/{id}/builds/{buildId} | jq '.data.actorDefinition.input'
```

Ambos endpoints son públicos y no requieren autenticación. Los precios reflejan el tier **FREE/BRONZE**; los tiers GOLD+ son 25–50% más baratos.

Lo que **no** se pudo verificar contra una fuente en vivo está marcado explícitamente con ⚠️ o bajo un encabezado "Sin verificar" en cada documento. Lo más relevante: el nombre del campo de email en el output de `harvestapi` y `apimaestro`, que sigue sin confirmar.

## Mantenimiento

Estos actores cambian rápido — casi todos los catalogados se modificaron en los últimos 30 días. Antes de confiar en un schema documentado acá para código nuevo, verificalo contra el endpoint de builds. La alternativa estructural, descrita en [input-schemas.md](apify-api/references/input-schemas.md), es que el gem obtenga y valide schemas en tiempo de codegen en vez de mantener copias a mano.

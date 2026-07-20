# Webhooks

**Los webhooks son la respuesta correcta al problema del 408.** Si se registra uno al arrancar el run, una conexión rota deja de significar perder el run.

## Eventos

```
ACTOR.RUN.CREATED
ACTOR.RUN.SUCCEEDED
ACTOR.RUN.FAILED
ACTOR.RUN.ABORTED
ACTOR.RUN.TIMED_OUT
ACTOR.RUN.RESURRECTED
ACTOR.BUILD.*
TEST
```

> ⚠️ **Inconsistencia real:** el evento de webhook es `TIMED_OUT` (guión bajo), el estado del run es `TIMED-OUT` (guión). No son intercambiables.

## Webhooks ad-hoc al arrancar un run

El parámetro `webhooks` de los endpoints de run acepta un array JSON **stringificado y codificado en base64**, luego URL-encodeado:

```ruby
webhooks_param = Base64.strict_encode64(JSON.generate([
  {
    eventTypes: %w[ACTOR.RUN.SUCCEEDED ACTOR.RUN.FAILED ACTOR.RUN.TIMED_OUT ACTOR.RUN.ABORTED],
    requestUrl: "https://ejemplo.com/webhooks/apify",
    idempotencyKey: SecureRandom.uuid
  }
]))
```

Campos disponibles: `requestUrl`, `eventTypes`, `condition`, `payloadTemplate`, `headersTemplate`, `description`, `shouldInterpolateStrings`, `idempotencyKey`, `ignoreSslErrors`, `isAdHoc`.

## Payload por defecto

```json
{
  "userId": {{userId}},
  "createdAt": {{createdAt}},
  "eventType": {{eventType}},
  "eventData": {{eventData}},
  "resource": {{resource}}
}
```

Más un objeto `globals` con `dateISO` y `dateUnix`.

`eventData` trae `actorId` y `actorRunId`. `resource` trae el objeto Run completo — incluido `defaultDatasetId`, que es lo que hace falta para ir a buscar los resultados.

## Reintentos e idempotencia

| Aspecto | Valor |
|---|---|
| Reintentos | Backoff exponencial, **máx. 11** (≈1min, 2min, 4min… el último a ~32h) |
| Respuesta esperada | **2XX** |
| Timeout del request | **2 minutos** |

> Textual de la documentación: *"In rare cases, the webhook might be invoked more than once. Design your code to be idempotent."*

`idempotencyKey` debe ser un UUID o un string de alta entropía. **Usarlo siempre** — con hasta 11 reintentos y entrega potencialmente duplicada, un handler no idempotente va a duplicar perfiles o cobros.

## Nota de scoping de tokens

Los webhooks heredan el scope del token que los creó. Los schedules, en cambio, siempre reciben un token sin scope. Si el gem llega a usar tokens con scope, tenerlo presente.

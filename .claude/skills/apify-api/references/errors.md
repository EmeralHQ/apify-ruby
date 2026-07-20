# Errores de Apify y mapeo a excepciones Ruby

## Formato

```json
{"error": {"type": "record-not-found", "message": "Store was not found."}}
```

`ErrorClassifier.parse_error_body` ya lo maneja correctamente.

## Errores comunes documentados

| HTTP | `type` |
|---|---|
| 400 | `invalid-request`, `invalid-value`, `invalid-record-key` |
| 401 | `token-not-provided` |
| 404 | `record-not-found` |
| 405 | `method-not-allowed` |
| 429 | `rate-limit-exceeded` |

## Catálogo completo por categoría

El enum completo de `type` (~370 valores) se puede extraer de `https://docs.apify.com/api/v2/act-runs-post.md`.

### Autenticación → `Apify::AuthenticationError`
```
token-not-provided, invalid-token, invalid-token-type, missing-api-token,
insufficient-permissions, elevated-permissions-needed, own-token-required
```

### No encontrado → falta una excepción dedicada
```
record-not-found, actor-not-found, build-not-found,
default-dataset-not-found, requested-dataset-view-does-not-exist
```
> El gem hoy mapea estos a `ApiError` genérico. Un `Apify::NotFoundError` sería útil — `actor-not-found` es un error de programación (actor ID mal escrito), no transitorio, y merece distinguirse.

### Validación → falta una excepción dedicada
```
invalid-input, invalid-input-schema, invalid-value, invalid-parameter,
invalid-build, parameter-required, schema-validation-error,
run-input-body-not-valid-json, input-json-not-object, input-json-too-long,
unknown-build-tag
```
> Muy relevante para este gem: `invalid-input` es lo que devuelve Apify cuando el `input` no cumple el schema del actor. Un `Apify::InvalidInputError` con el mensaje del schema haría el debugging mucho más rápido.

### Límites → `Apify::RateLimitError` / `Apify::TransientError`
```
rate-limit-exceeded, too-many-requests, limit-reached,
concurrent-runs-limit-exceeded, actor-memory-limit-exceeded,
run-timeout-exceeded, record-too-large, request-too-large
```
> `ErrorClassifier` ya cubre `rate-limit-exceeded`, `too-many-requests` y `run-timeout-exceeded`.
> **Falta `concurrent-runs-limit-exceeded`** — es transitorio y reintentable, y con límites de 25 runs concurrentes en plan Free es fácil de topar.

### Facturación / rental → `Apify::BillingError`
```
actor-is-not-rented, cannot-rent-paid-actor,
not-enough-usage-to-run-paid-actor, apify-plan-required-to-use-paid-actor,
failed-to-charge-user, no-payment-method-available,
max-items-must-be-greater-than-zero, max-total-charge-usd-below-minimum
```
> `ErrorClassifier::BILLING_ERROR_TYPES` ya cubre 4 de estos.
> **Faltan** `actor-is-not-rented` y `cannot-rent-paid-actor`, que van a aparecer con los actores rental (`bebity~*`). Merecen un mensaje dedicado: para quien usa el gem, "el actor no está alquilado" es un fallo poco obvio y la acción correcta (alquilarlo en la Consola) no es evidente desde un `ApiError` genérico.

### Ciclo de vida
```
actor-run-failed, run-failed, actor-disabled, build-outdated, dataset-locked
```

### Transporte → `Apify::TransientError`
```
internal-server-error, operation-timed-out, socket-closed,
request-aborted-prematurely
```
> **Ninguno de estos está en las listas del `ErrorClassifier` actual.** Se capturan igual por la regla `http_code >= 500`, pero si Apify los devolviera con un 4xx quedarían mal clasificados como permanentes.

## ❌ Corrección importante

**`monthly-usage-hard-limit-exceeded` no existe.** Cero ocurrencias en el schema. Los vecinos reales son:
```
monthly-usage-limit-too-low
not-enough-usage-to-run-paid-actor
limit-reached
```
Si aparece en código o docs del gem, está mal.

## Gaps del `ErrorClassifier` actual

Resumen de lo que conviene agregar, ordenado por impacto:

1. **`concurrent-runs-limit-exceeded`** a los tipos reintentables — fácil de topar en plan Free.
2. **`Apify::InvalidInputError`** para la familia de validación — el error más frecuente en desarrollo.
3. **`actor-is-not-rented` / `cannot-rent-paid-actor`** a `BILLING_ERROR_TYPES` con mensaje accionable.
4. **`Apify::NotFoundError`** para distinguir errores de programación de fallos de plataforma.
5. Los tipos de transporte a `TRANSIENT_ERROR_TYPES` explícitos, no solo por rango 5xx.

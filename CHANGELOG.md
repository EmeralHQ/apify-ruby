## [Unreleased]

- Add LinkedIn/Apify knowledge base under `.claude/skills` (actor catalog, API mechanics, cost control, compliance)

## [0.2.0] - 2026-07-10

- Add `Apify::Client` with Bearer auth and configurable timeouts
- Add `Apify.actors.run_sync_get_dataset_items` for sync actor runs
- Add typed errors with Apify API error classification (`ErrorClassifier`)
- Add optional exponential retry via `config.max_retries` (default: 0, opt-in)

## [0.1.0] - 2026-07-10

- Initial release

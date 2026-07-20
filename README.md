# Apify

Ruby client for the [Apify API v2](https://docs.apify.com/api/v2). Runs actors, returns raw Apify responses, and raises typed errors for Apify API failures. Retries are opt-in via configuration.

Distributed as a private gem via GitHub.

## Installation

Add to your `Gemfile`:

```ruby
# Production (GitHub)
gem "apify", github: "EmeralHQ/apify-ruby", branch: "main"

# Local development
gem "apify", path: "../apify-ruby"
```

Then:

```bash
bundle install
```

Configure in a Rails initializer:

```ruby
require "apify"

Apify.configure do |config|
  config.api_token = ENV.fetch("APIFY_API_TOKEN")
  config.read_timeout = 310
  config.logger = Rails.logger
  # Optional: retry transient/rate-limit errors (default max_retries is 0)
  config.max_retries = 2
  config.retry_base_delay = 1
  config.retry_max_delay = 30
end
```

## Errors

Failed API responses are classified from HTTP status and Apify's `error.type` field (e.g. `rate-limit-exceeded` on HTTP 400) and raised as typed exceptions such as `Apify::AuthenticationError`, `Apify::BillingError`, `Apify::RateLimitError`, and `Apify::TransientError`.

Retries are disabled by default. Set `config.max_retries` to enable exponential backoff for retryable errors. When Apify responds with a `Retry-After` header (e.g. on HTTP 429), the client waits that long instead of the computed backoff. Otherwise, retry delays use full jitter (a random value between 50% and 100% of the exponential backoff) to avoid thundering-herd retries across concurrent workers, and every wait is capped at `retry_max_delay` seconds.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_token` | String | `nil` | **Required.** Your Apify API token |
| `base_url` | String | `"https://api.apify.com/v2"` | Apify API base URL |
| `open_timeout` | Integer | `10` | Connection open timeout in seconds |
| `read_timeout` | Integer | `310` | Response read timeout in seconds |
| `max_retries` | Integer | `0` | Number of retries for transient/rate-limit errors (0 disables retries) |
| `retry_base_delay` | Integer | `1` | Base delay in seconds for exponential backoff between retries |
| `retry_max_delay` | Integer | `30` | Maximum delay in seconds for a single retry wait, regardless of backoff or `Retry-After` |
| `logger` | Object | `nil` | Logger used to record retry/error events |
| `user_agent` | String | `"ApifyRuby/<version>"` | User-Agent header sent with requests |
| `sleep_fn` | Proc | `->(seconds) { sleep(seconds) }` | Sleep implementation used between retries (override for testing) |

## Usage

```ruby
items = Apify.actors.run_sync_get_dataset_items(
  actor_id: "dev_fusion~linkedin-profile-scraper",
  input:    { profileUrls: ["https://www.linkedin.com/in/example"] }
)
# => [{ "fullName" => "...", ... }]  # raw Apify dataset items
```

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
```

## Contributing

Bug reports and pull requests are welcome on [EmeralHQ/apify-ruby](https://github.com/EmeralHQ/apify-ruby).

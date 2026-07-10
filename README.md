# Apify

Ruby client for the [Apify API v2](https://docs.apify.com/api/v2). Runs actors, returns raw Apify responses, and raises typed errors for Apify API failures. Retries are opt-in via configuration.

Distributed as a private gem via GitHub (same pattern as [openfactura-ruby](https://github.com/EmeralHQ/openfactura-ruby)).

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
end
```

## Errors

Failed API responses are classified from HTTP status and Apify's `error.type` field (e.g. `rate-limit-exceeded` on HTTP 400) and raised as typed exceptions such as `Apify::AuthenticationError`, `Apify::BillingError`, `Apify::RateLimitError`, and `Apify::TransientError`.

Retries are disabled by default. Set `config.max_retries` to enable exponential backoff for retryable errors.

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

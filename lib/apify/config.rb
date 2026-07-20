# frozen_string_literal: true

require "dry-configurable"

module Apify
  class Config
    extend Dry::Configurable

    setting :api_token, default: nil
    setting :base_url, default: "https://api.apify.com/v2"
    setting :open_timeout, default: 10
    setting :read_timeout, default: 310
    setting :max_retries, default: 0
    setting :retry_base_delay, default: 1
    setting :retry_max_delay, default: 30
    setting :logger, default: nil
    setting :user_agent, default: "ApifyRuby/#{Apify::VERSION}"
    setting :sleep_fn, default: ->(seconds) { sleep(seconds) }

    def self.validate!(target = config)
      raise ConfigurationError, "API token is required" if target.api_token.to_s.strip.empty?
    end
  end
end

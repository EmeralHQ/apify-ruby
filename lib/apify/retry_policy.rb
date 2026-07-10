# frozen_string_literal: true

module Apify
  class RetryPolicy
    def initialize(config: Config.config)
      @config = config
    end

    def call(context: "Apify::Client")
      attempts = 0

      begin
        attempts += 1
        yield
      rescue TransientError => e
        log_error(context: context, error: e)
        raise if attempts > @config.max_retries

        warn_retry(context: context, attempt: attempts, backoff_seconds: backoff_for(attempts))
        @config.sleep_fn.call(backoff_for(attempts))
        retry
      end
    end

    private

    def backoff_for(attempts)
      @config.retry_base_delay * (2**(attempts - 1))
    end

    def log_error(context:, error:)
      return unless @config.logger

      status_code = error.status_code || "unknown"
      response_body = sanitize_response_body(error.response_body)

      @config.logger.error(
        "[#{context}] Apify provider error " \
        "class=#{error.class.name} " \
        "status=#{status_code} " \
        "message=#{error.message} " \
        "response_body=#{response_body || "none"}"
      )
    end

    def warn_retry(context:, attempt:, backoff_seconds:)
      return unless @config.logger

      max_attempts = @config.max_retries + 1
      @config.logger.warn(
        "[#{context}] Retrying transient Apify provider error in #{backoff_seconds}s " \
        "(attempt #{attempt}/#{max_attempts})"
      )
    end

    def sanitize_response_body(response_body)
      return nil if response_body.nil? || response_body.to_s.strip.empty?

      raw_body = response_body.is_a?(String) ? response_body : response_body.to_json
      raw_body.gsub(/(token=)[^&\s"]+/i, '\1[FILTERED]')[0, 1_000]
    rescue StandardError
      "[unserializable response body]"
    end
  end
end

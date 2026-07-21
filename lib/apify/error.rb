# frozen_string_literal: true

module Apify
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class ParseError < Error; end

  class ApiError < Error
    attr_reader :status_code, :response_body, :error_type, :code, :retry_after

    # rubocop:disable Metrics/ParameterLists -- retry_after adds a 6th keyword; splitting
    # into an options hash would ripple through every subclass's initialize signature.
    def initialize(message, status_code: nil, response_body: nil, error_type: nil, code: "apify_error",
                   retry_after: nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
      @error_type = error_type
      @code = code
      @retry_after = retry_after
    end
    # rubocop:enable Metrics/ParameterLists

    def retryable?
      false
    end
  end

  class TransientError < ApiError
    def retryable?
      true
    end
  end

  class RateLimitError < TransientError; end

  class EmptyResultError < TransientError
    def initialize(message = "Actor finished with no dataset items", status_code: nil, response_body: nil,
                   error_type: nil)
      super(
        message,
        status_code: status_code,
        response_body: response_body,
        error_type: error_type,
        code: "empty_result"
      )
    end
  end

  class AuthenticationError < ApiError
    def initialize(message = "Authentication failed", status_code: 401, response_body: nil, error_type: nil)
      super(
        message,
        status_code: status_code,
        response_body: response_body,
        error_type: error_type,
        code: "authentication_error"
      )
    end
  end

  class BillingError < ApiError
    def initialize(message = "Billing error", status_code: 402, response_body: nil, error_type: nil)
      super(
        message,
        status_code: status_code,
        response_body: response_body,
        error_type: error_type,
        code: "billing_error"
      )
    end
  end

  class TimeoutError < ApiError
    def initialize(message = "Request timeout", status_code: 408, response_body: nil, error_type: nil)
      super(
        message,
        status_code: status_code,
        response_body: response_body,
        error_type: error_type,
        code: "timeout_error"
      )
    end
  end
end

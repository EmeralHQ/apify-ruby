# frozen_string_literal: true

require "json"

module Apify
  class ErrorClassifier
    RATE_LIMIT_ERROR_TYPES = %w[rate-limit-exceeded too-many-requests].freeze
    AUTH_ERROR_TYPES = %w[
      invalid-token
      token-not-provided
      user-or-token-not-found
      invalid-credentials
    ].freeze
    BILLING_ERROR_TYPES = %w[
      not-enough-usage-to-run-paid-actor
      failed-to-charge-user
      apify-plan-required-to-use-paid-actor
      x402-payment-required
    ].freeze
    TIMEOUT_ERROR_TYPES = %w[run-timeout-exceeded].freeze

    class << self
      def parse_error_body(response_body)
        return nil if response_body.nil? || response_body.to_s.strip.empty?

        error = JSON.parse(response_body).fetch("error", nil)
        return nil unless error.is_a?(Hash)

        type = error["type"]
        message = error["message"]
        {
          type: type.to_s.strip.empty? ? nil : type,
          message: message.to_s.strip.empty? ? nil : message
        }
      rescue JSON::ParserError
        nil
      end

      def classify(http_code:, fallback_message:, error_type: nil)
        code = http_code.to_i
        normalized_type = error_type.to_s.strip.empty? ? nil : error_type

        if retryable?(http_code: code, error_type: normalized_type)
          return { retryable: true, code: "apify_error", message: fallback_message }
        end

        {
          retryable: false,
          code: permanent_error_code(http_code: code, error_type: normalized_type),
          message: fallback_message
        }
      end

      def raise_from_response!(http_code:, response_body:, fallback_message: nil, retry_after: nil)
        parsed_error = parse_error_body(response_body)
        message = parsed_error&.dig(:message) || fallback_message ||
                  "Apify API returned HTTP #{http_code}"
        classification = classify(
          http_code: http_code,
          error_type: parsed_error&.dig(:type),
          fallback_message: message
        )
        error_type = parsed_error&.dig(:type)
        options = {
          status_code: http_code,
          response_body: response_body,
          error_type: error_type
        }

        if classification[:retryable]
          exception_class = retry_exception_class(http_code: http_code, error_type: error_type)
          raise exception_class.new(message, code: classification[:code], retry_after: parse_retry_after(retry_after),
                                             **options)
        end

        raise exception_for_code(classification[:code], message, **options)
      end

      private

      # Retry-After puede ser segundos ("30") o una fecha HTTP (RFC 7231).
      # Solo soportamos el formato de segundos; una fecha se trata como nil
      # (backoff_for calculará el delay como si no hubiera header).
      def parse_retry_after(value)
        return nil if value.nil?

        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def retry_exception_class(http_code:, error_type:)
        if rate_limit_error?(http_code: http_code.to_i, error_type: error_type)
          RateLimitError
        else
          TransientError
        end
      end

      def retryable?(http_code:, error_type:)
        return true if http_code == 429
        return true if http_code >= 500
        return true if error_type && RATE_LIMIT_ERROR_TYPES.include?(error_type)

        false
      end

      def rate_limit_error?(http_code:, error_type:)
        http_code == 429 ||
          (error_type && RATE_LIMIT_ERROR_TYPES.include?(error_type))
      end

      def permanent_error_code(http_code:, error_type:)
        return http_status_error_code(http_code) if http_status_error_code(http_code)

        type_error_code(error_type) || "apify_error"
      end

      def http_status_error_code(http_code)
        {
          401 => "authentication_error",
          403 => "authentication_error",
          402 => "billing_error",
          408 => "timeout_error"
        }[http_code]
      end

      def type_error_code(error_type)
        return nil if error_type.nil?

        return "authentication_error" if AUTH_ERROR_TYPES.include?(error_type)
        return "billing_error" if BILLING_ERROR_TYPES.include?(error_type)
        return "timeout_error" if TIMEOUT_ERROR_TYPES.include?(error_type)

        nil
      end

      def exception_for_code(code, message, **)
        case code
        when "authentication_error"
          AuthenticationError.new(message, **)
        when "billing_error"
          BillingError.new(message, **)
        when "timeout_error"
          TimeoutError.new(message, **)
        else
          ApiError.new(message, code: code, **)
        end
      end
    end
  end
end

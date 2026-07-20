# frozen_string_literal: true

require "json"
require "httparty"
require "net/http"
require "openssl"
require "erb"

module Apify
  class Client
    include HTTParty

    NETWORK_ERRORS = [
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::EPIPE,
      SocketError,
      EOFError,
      IOError,
      Net::HTTPBadResponse
    ].freeze

    ACTOR_ID_FORMAT = /\A[\w.-]+(~[\w.-]+)?\z/

    def initialize(config: Config.config, retry_policy: nil)
      @config = config
      Config.validate!(@config)
      @retry_policy = retry_policy || RetryPolicy.new(config: config)
      self.class.base_uri(config.base_url)
    end

    def post_sync_dataset_items(actor_id, input, read_timeout: nil)
      actor_id = validate_actor_id!(actor_id)
      path = "/actors/#{ERB::Util.url_encode(actor_id)}/run-sync-get-dataset-items"

      @retry_policy.call(context: "Apify::Client#post_sync_dataset_items") do
        execute_post(path, input, read_timeout: read_timeout)
      end
    end

    private

    attr_reader :config

    def validate_actor_id!(actor_id)
      actor_id = actor_id.to_s
      return actor_id if actor_id.match?(ACTOR_ID_FORMAT)

      raise ArgumentError, "Invalid Apify actor_id format: #{actor_id.inspect}"
    end

    def execute_post(path, input, read_timeout:)
      response = post_request(path, input, read_timeout: read_timeout)
      handle_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
      raise TransientError, "Request timeout: #{e.message}"
    rescue OpenSSL::SSL::SSLError => e
      raise TransientError, "SSL error: #{e.message}"
    rescue *NETWORK_ERRORS => e
      raise TransientError, "Network error: #{e.class}: #{e.message}"
    end

    def post_request(path, input, read_timeout:)
      self.class.post(
        path,
        headers: request_headers,
        body: input.to_json,
        timeout: read_timeout || config.read_timeout,
        open_timeout: config.open_timeout
      )
    end

    def request_headers
      {
        "Authorization" => "Bearer #{config.api_token}",
        "Content-Type" => "application/json",
        "User-Agent" => config.user_agent
      }
    end

    def handle_response(response)
      case response.code
      when 200..299
        parse_success_body(response.body)
      else
        ErrorClassifier.raise_from_response!(
          http_code: response.code,
          response_body: response.body,
          fallback_message: "Apify API returned HTTP #{response.code}: #{response.body.to_s[0..200]}"
        )
      end
    end

    def parse_success_body(body)
      return [] if body.nil? || body.to_s.strip.empty?

      parsed = JSON.parse(body)
      raise ParseError, "Unexpected response format from Apify" unless parsed.is_a?(Array)

      parsed
    rescue JSON::ParserError => e
      raise ParseError, "Invalid JSON response from Apify: #{e.message}"
    end
  end
end

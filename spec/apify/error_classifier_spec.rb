# frozen_string_literal: true

RSpec.describe Apify::ErrorClassifier do
  describe ".classify" do
    it "marks rate limit responses as retryable" do
      result = described_class.classify(
        http_code: 429,
        error_type: "rate-limit-exceeded",
        fallback_message: "Too many requests"
      )

      expect(result[:retryable]).to be(true)
    end

    it "maps authentication failures to authentication_error" do
      result = described_class.classify(
        http_code: 401,
        fallback_message: "Unauthorized"
      )

      expect(result).to eq(
        retryable: false,
        code: "authentication_error",
        message: "Unauthorized"
      )
    end

    it "maps billing failures to billing_error" do
      result = described_class.classify(
        http_code: 402,
        error_type: "not-enough-usage-to-run-paid-actor",
        fallback_message: "Not enough usage to run paid Actor"
      )

      expect(result).to eq(
        retryable: false,
        code: "billing_error",
        message: "Not enough usage to run paid Actor"
      )
    end
  end

  describe ".raise_from_response!" do
    it "raises billing error for HTTP 402 payloads" do
      body = {
        error: {
          type: "not-enough-usage-to-run-paid-actor",
          message: "Not enough usage to run paid Actor"
        }
      }.to_json

      expect do
        described_class.raise_from_response!(http_code: 402, response_body: body)
      end.to raise_error(Apify::BillingError)
    end

    it "raises transient error for retryable HTTP 503 payloads" do
      expect do
        described_class.raise_from_response!(
          http_code: 503,
          response_body: "Service Unavailable",
          fallback_message: "Apify API returned HTTP 503: Service Unavailable"
        )
      end.to raise_error(Apify::TransientError)
    end
  end
end

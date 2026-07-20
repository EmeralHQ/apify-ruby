# frozen_string_literal: true

# Records log calls so specs can assert on message content without coupling
# to call order or stubbing a real Logger.
class RetryPolicySpecRecordingLogger
  Entry = Struct.new(:level, :message)

  attr_reader :entries

  def initialize
    @entries = []
  end

  def error(message)
    @entries << Entry.new(:error, message)
  end

  def warn(message)
    @entries << Entry.new(:warn, message)
  end

  def messages
    entries.map(&:message)
  end
end

# to_json raises for this object, exercising the sanitize_response_body
# rescue branch that falls back to "[unserializable response body]".
class RetryPolicySpecUnserializableBody
  def to_json(*_args)
    raise "cannot serialize"
  end
end

RSpec.describe Apify::RetryPolicy do
  def build_config(max_retries:, retry_base_delay: 1, logger: nil, sleep_fn: ->(_seconds) {})
    Struct.new(:max_retries, :retry_base_delay, :logger, :sleep_fn, keyword_init: true).new(
      max_retries: max_retries,
      retry_base_delay: retry_base_delay,
      logger: logger,
      sleep_fn: sleep_fn
    )
  end

  def build_policy(config)
    described_class.new(config: config)
  end

  describe "backoff" do
    it "sleeps with exponential backoff and re-raises after exhausting retries" do
      sleeps = []
      config = build_config(max_retries: 3, retry_base_delay: 1, sleep_fn: ->(seconds) { sleeps << seconds })
      policy = build_policy(config)

      expect do
        policy.call { raise Apify::TransientError, "boom" }
      end.to raise_error(Apify::TransientError)
      expect(sleeps).to eq([1, 2, 4])
    end

    it "scales sleeps with a different base delay and retry count" do
      sleeps = []
      config = build_config(max_retries: 2, retry_base_delay: 2, sleep_fn: ->(seconds) { sleeps << seconds })
      policy = build_policy(config)

      expect do
        policy.call { raise Apify::TransientError, "boom" }
      end.to raise_error(Apify::TransientError)
      expect(sleeps).to eq([2, 4])
    end

    it "runs the block once and re-raises immediately when max_retries is 0" do
      sleeps = []
      call_count = 0
      config = build_config(max_retries: 0, sleep_fn: ->(seconds) { sleeps << seconds })
      policy = build_policy(config)

      expect do
        policy.call do
          call_count += 1
          raise Apify::TransientError, "boom"
        end
      end.to raise_error(Apify::TransientError)
      expect(sleeps).to eq([])
      expect(call_count).to eq(1)
    end

    it "does not rescue or sleep for non-transient errors" do
      sleeps = []
      config = build_config(max_retries: 3, sleep_fn: ->(seconds) { sleeps << seconds })
      policy = build_policy(config)

      expect do
        policy.call { raise Apify::ApiError, "permanent failure" }
      end.to raise_error(Apify::ApiError)
      expect(sleeps).to eq([])
    end

    it "returns the block's value once it succeeds on a later attempt" do
      sleeps = []
      attempts = 0
      config = build_config(max_retries: 1, retry_base_delay: 1, sleep_fn: ->(seconds) { sleeps << seconds })
      policy = build_policy(config)

      result = policy.call do
        attempts += 1
        raise Apify::TransientError, "boom" if attempts == 1

        "success"
      end

      expect(result).to eq("success")
      expect(sleeps).to eq([1])
    end
  end

  describe "logging" do
    it "logs an error for each failure and a warn for each retry" do
      logger = RetryPolicySpecRecordingLogger.new
      config = build_config(max_retries: 1, retry_base_delay: 1, logger: logger)
      policy = build_policy(config)
      error = Apify::TransientError.new("Service down", status_code: 500, response_body: "boom body")

      expect { policy.call { raise error } }.to raise_error(Apify::TransientError)
      expect(logger.messages).to include(
        a_string_matching(/class=Apify::TransientError status=500 message=Service down response_body=boom body/)
      )
      expect(logger.messages).to include(a_string_matching(%r{attempt 1/2}))
    end

    it "does not raise when no logger is configured" do
      attempts = 0
      config = build_config(max_retries: 1, retry_base_delay: 1, logger: nil)
      policy = build_policy(config)

      result = policy.call do
        attempts += 1
        raise Apify::TransientError, "boom" if attempts == 1

        "ok"
      end

      expect(result).to eq("ok")
    end
  end

  describe "response body sanitization" do
    it "filters token values out of the logged response body" do
      logger = RetryPolicySpecRecordingLogger.new
      config = build_config(max_retries: 0, logger: logger)
      policy = build_policy(config)

      expect do
        policy.call do
          raise Apify::TransientError.new("boom", response_body: "ok token=SECRETO123 fin")
        end
      end.to raise_error(Apify::TransientError)
      expect(logger.messages.last).to include("token=[FILTERED]")
      expect(logger.messages.last).not_to include("SECRETO123")
    end

    it "truncates a logged response body over 1000 characters" do
      logger = RetryPolicySpecRecordingLogger.new
      config = build_config(max_retries: 0, logger: logger)
      policy = build_policy(config)
      long_body = "a" * 1500

      expect do
        policy.call { raise Apify::TransientError.new("boom", response_body: long_body) }
      end.to raise_error(Apify::TransientError)
      expect(logger.messages.last).to include("a" * 1000)
      expect(logger.messages.last).not_to include("a" * 1001)
    end

    it "falls back to a placeholder when the response body cannot be serialized" do
      logger = RetryPolicySpecRecordingLogger.new
      config = build_config(max_retries: 0, logger: logger)
      policy = build_policy(config)
      unserializable_body = RetryPolicySpecUnserializableBody.new

      expect do
        policy.call { raise Apify::TransientError.new("boom", response_body: unserializable_body) }
      end.to raise_error(Apify::TransientError)
      expect(logger.messages.last).to include("[unserializable response body]")
    end
  end
end

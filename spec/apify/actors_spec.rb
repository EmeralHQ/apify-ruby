# frozen_string_literal: true

RSpec.describe Apify::Actors do
  let(:linkedin_url) { "https://www.linkedin.com/in/williamhgates" }
  let(:input) { { profileUrls: [linkedin_url] } }

  # Builds a Client for the given base_url/token, stubs its dataset-items endpoint
  # to return a profile unique to that host, and returns [client, profile].
  def client_and_profile_for(base_url:, token:)
    config_struct = Struct.new(
      :api_token, :base_url, :open_timeout, :read_timeout, :run_timeout_secs, :max_retries,
      :retry_base_delay, :retry_max_delay, :logger, :user_agent, :sleep_fn
    )
    config = config_struct.new(token, base_url, 10, 310, nil, 0, 1, 30, nil, "ApifyRuby/test", ->(_seconds) {})
    profile = { "fullName" => "Profile for #{base_url}" }
    url = "#{base_url}/actors/#{ApifyHelpers::ACTOR_ID}/run-sync-get-dataset-items"
    stub_request(:post, url)
      .with(headers: { "Authorization" => "Bearer #{token}" })
      .to_return(status: 200, body: [profile].to_json)

    [Apify::Client.new(config: config), profile]
  end

  describe "#run_sync_get_dataset_items" do
    it "returns dataset items on success" do
      profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
      stub_sync_dataset_items_success(body: [profile].to_json)

      items = described_class.new(Apify.client).run_sync_get_dataset_items(
        actor_id: ApifyHelpers::ACTOR_ID,
        input: input
      )

      expect(items).to eq([profile])
    end

    it "returns empty array when dataset is empty and retries are disabled" do
      stub_sync_dataset_items_success(body: [].to_json)

      items = described_class.new(Apify.client).run_sync_get_dataset_items(
        actor_id: ApifyHelpers::ACTOR_ID,
        input: input
      )

      expect(items).to eq([])
      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "returns empty array when response body is blank and retries are disabled" do
      stub_sync_dataset_items_success(body: "")

      items = described_class.new(Apify.client).run_sync_get_dataset_items(
        actor_id: ApifyHelpers::ACTOR_ID,
        input: input
      )

      expect(items).to eq([])
      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "raises configuration error when api token is missing" do
      Apify.reset!
      Apify.configure { |config| config.api_token = nil }

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::ConfigurationError, "API token is required")
    end

    it "validates and uses the injected config instead of the global config" do
      Apify.reset!
      Apify.configure { |config| config.api_token = nil }

      injected_config = Struct.new(
        :api_token, :base_url, :open_timeout, :read_timeout, :run_timeout_secs, :max_retries,
        :retry_base_delay, :retry_max_delay, :logger, :user_agent, :sleep_fn
      ).new(
        "injected-token", ApifyHelpers::API_BASE, 10, 310, nil, 0, 1, 30, nil, "ApifyRuby/test", ->(_seconds) {}
      )
      profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
      stub_request(:post, sync_dataset_items_url)
        .with(headers: { "Authorization" => "Bearer injected-token" })
        .to_return(status: 200, body: [profile].to_json)

      client = Apify::Client.new(config: injected_config)
      items = client.post_sync_dataset_items(ApifyHelpers::ACTOR_ID, input)

      expect(items).to eq([profile])
    end

    it "isolates the base_url between instances, even when the first client is used last" do
      first_client, first_profile = client_and_profile_for(
        base_url: "https://host-a.example.com/v2", token: "token-a"
      )
      second_client, second_profile = client_and_profile_for(
        base_url: "https://host-b.example.com/v2", token: "token-b"
      )

      # Use the second client first, then the first client last: with a shared
      # class-level base_uri, this last call would incorrectly hit host-b.
      expect(second_client.post_sync_dataset_items(ApifyHelpers::ACTOR_ID, input)).to eq([second_profile])
      expect(first_client.post_sync_dataset_items(ApifyHelpers::ACTOR_ID, input)).to eq([first_profile])
    end

    it "raises authentication error when apify responds with 401" do
      stub_sync_dataset_items_error(status: 401, body: "Unauthorized")

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::AuthenticationError)

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "raises billing error when apify responds with 402" do
      body = {
        error: {
          type: "not-enough-usage-to-run-paid-actor",
          message: "Not enough usage to run paid Actor"
        }
      }.to_json
      stub_sync_dataset_items_error(status: 402, body: body)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::BillingError) { |error|
        expect(error.message).to eq("Not enough usage to run paid Actor")
      }

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "raises timeout error when apify responds with 408" do
      body = {
        error: {
          type: "run-timeout-exceeded",
          message: "Actor run exceeded the timeout of 300 seconds for this API endpoint"
        }
      }.to_json
      stub_sync_dataset_items_error(status: 408, body: body)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::TimeoutError) { |error|
        expect(error.message).to include("300 seconds")
      }

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "does not retry by default on HTTP 503" do
      stub_sync_dataset_items_error(status: 503, body: "Service Unavailable")

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::TransientError)

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "does not retry by default on HTTP 400 rate-limit-exceeded" do
      rate_limit_body = {
        error: {
          type: "rate-limit-exceeded",
          message: "Too many requests"
        }
      }.to_json
      stub_sync_dataset_items_error(status: 400, body: rate_limit_body)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::RateLimitError)

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "raises transient error when connection is refused" do
      stub_request(:post, sync_dataset_items_url)
        .with(headers: { "Authorization" => "Bearer test-apify-token" })
        .to_raise(Errno::ECONNREFUSED)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::TransientError)

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    it "raises transient error on socket error" do
      stub_request(:post, sync_dataset_items_url)
        .with(headers: { "Authorization" => "Bearer test-apify-token" })
        .to_raise(SocketError)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::TransientError)

      expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
    end

    context "with retries enabled" do
      before do
        Apify.reset!
        Apify.configure do |config|
          config.api_token = "test-apify-token"
          config.max_retries = 2
          config.sleep_fn = ->(_seconds) {}
        end
      end

      it "retries on HTTP 400 rate-limit-exceeded and succeeds on the next attempt" do
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
        rate_limit_body = {
          error: {
            type: "rate-limit-exceeded",
            message: "Too many requests"
          }
        }.to_json

        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_return(status: 400, body: rate_limit_body)
          .then
          .to_return(status: 200, body: [profile].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).twice
      end

      it "retries on HTTP 429 honoring the Retry-After header" do
        sleeps = []
        Apify.configure { |config| config.sleep_fn = ->(seconds) { sleeps << seconds } }
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }

        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_return(status: 429, headers: { "Retry-After" => "3" }, body: "Too Many Requests")
          .then
          .to_return(status: 200, body: [profile].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([profile])
        expect(sleeps).to eq([3])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).twice
      end

      it "retries on HTTP 503 and succeeds on the next attempt" do
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }

        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_return(status: 503, body: "Service Unavailable")
          .then
          .to_return(status: 200, body: [profile].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).twice
      end

      it "retries on timeout and succeeds on the third attempt" do
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }

        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_raise(Net::ReadTimeout)
          .then
          .to_raise(Net::ReadTimeout)
          .then
          .to_return(status: 200, body: [profile].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).times(3)
      end

      it "retries on connection reset and succeeds on the next attempt" do
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }

        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_raise(Errno::ECONNRESET)
          .then
          .to_return(status: 200, body: [profile].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).twice
      end

      it "raises after exhausting retries on persistent HTTP 503" do
        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_return(status: 503, body: "Service Unavailable")

        expect do
          Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
        end.to raise_error(Apify::TransientError) { |error|
          expect(error.message).to include("HTTP 503")
        }

        expect(WebMock).to have_requested(:post, sync_dataset_items_url).times(3)
      end

      it "retries on empty dataset and succeeds on a later attempt" do
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }

        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_return(status: 201, body: [].to_json)
          .then
          .to_return(status: 201, body: [].to_json)
          .then
          .to_return(status: 201, body: [profile].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).times(3)
      end

      it "returns empty array after exhausting retries on empty dataset" do
        stub_request(:post, sync_dataset_items_url)
          .with(headers: { "Authorization" => "Bearer test-apify-token" })
          .to_return(status: 201, body: [].to_json)

        items = Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)

        expect(items).to eq([])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url).times(3)
      end
    end

    it "raises parse error when response is not a JSON array" do
      stub_sync_dataset_items_success(body: { "unexpected" => "object" }.to_json)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::ParseError, "Unexpected response format from Apify")
    end

    it "raises argument error and makes no request for a path-traversal actor_id" do
      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: "foo/../../otra-ruta", input: input)
      end.to raise_error(ArgumentError, /Invalid Apify actor_id/)

      expect(WebMock).not_to have_requested(:post, /apify/)
    end

    it "raises argument error and makes no request for an actor_id with a query string" do
      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: "foo?token=x", input: input)
      end.to raise_error(ArgumentError, /Invalid Apify actor_id/)

      expect(WebMock).not_to have_requested(:post, /apify/)
    end

    context "with run_timeout_secs" do
      it "omits the timeout query when neither config nor kwarg is set" do
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
        stub_sync_dataset_items_success(body: [profile].to_json)

        described_class.new(Apify.client).run_sync_get_dataset_items(
          actor_id: ApifyHelpers::ACTOR_ID,
          input: input
        )

        expect(WebMock).to have_requested(:post, sync_dataset_items_url).once
        expect(WebMock).not_to have_requested(:post, sync_dataset_items_url(timeout: 13))
      end

      it "passes config.run_timeout_secs as the timeout query param" do
        Apify.reset!
        Apify.configure do |config|
          config.api_token = "test-apify-token"
          config.run_timeout_secs = 13
        end
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
        stub_sync_dataset_items_success(body: [profile].to_json, timeout: 13)

        items = Apify.actors.run_sync_get_dataset_items(
          actor_id: ApifyHelpers::ACTOR_ID,
          input: input
        )

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url(timeout: 13)).once
      end

      it "lets the per-call run_timeout_secs kwarg override config" do
        Apify.reset!
        Apify.configure do |config|
          config.api_token = "test-apify-token"
          config.run_timeout_secs = 13
        end
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
        stub_sync_dataset_items_success(body: [profile].to_json, timeout: 20)

        items = Apify.actors.run_sync_get_dataset_items(
          actor_id: ApifyHelpers::ACTOR_ID,
          input: input,
          run_timeout_secs: 20
        )

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url(timeout: 20)).once
        expect(WebMock).not_to have_requested(:post, sync_dataset_items_url(timeout: 13))
      end

      it "falls back to config when the per-call kwarg is nil" do
        Apify.reset!
        Apify.configure do |config|
          config.api_token = "test-apify-token"
          config.run_timeout_secs = 13
        end
        profile = { "fullName" => "Bill Gates", "linkedinUrl" => linkedin_url }
        stub_sync_dataset_items_success(body: [profile].to_json, timeout: 13)

        items = Apify.actors.run_sync_get_dataset_items(
          actor_id: ApifyHelpers::ACTOR_ID,
          input: input,
          run_timeout_secs: nil
        )

        expect(items).to eq([profile])
        expect(WebMock).to have_requested(:post, sync_dataset_items_url(timeout: 13)).once
      end
    end
  end
end

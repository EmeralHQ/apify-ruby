# frozen_string_literal: true

RSpec.describe Apify::Actors do
  let(:linkedin_url) { "https://www.linkedin.com/in/williamhgates" }
  let(:input) { { profileUrls: [linkedin_url] } }

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

    it "raises configuration error when api token is missing" do
      Apify.reset!
      Apify.configure { |config| config.api_token = nil }

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::ConfigurationError, "API token is required")
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
    end

    it "raises parse error when response is not a JSON array" do
      stub_sync_dataset_items_success(body: { "unexpected" => "object" }.to_json)

      expect do
        Apify.actors.run_sync_get_dataset_items(actor_id: ApifyHelpers::ACTOR_ID, input: input)
      end.to raise_error(Apify::ParseError, "Unexpected response format from Apify")
    end
  end
end

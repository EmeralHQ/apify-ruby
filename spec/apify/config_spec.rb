# frozen_string_literal: true

RSpec.describe Apify::Config do
  it "defaults max_retries to 0" do
    expect(described_class.settings[:max_retries].default).to eq(0)
  end

  describe ".validate!" do
    it "raises when api token is missing" do
      described_class.configure do |config|
        config.api_token = nil
      end

      expect { described_class.validate! }.to raise_error(Apify::ConfigurationError)
    end

    it "passes when api token is configured" do
      described_class.configure do |config|
        config.api_token = "token"
      end

      expect { described_class.validate! }.not_to raise_error
    end
  end
end

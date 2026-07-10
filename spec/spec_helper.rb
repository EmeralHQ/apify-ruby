# frozen_string_literal: true

require "apify"
require "webmock/rspec"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.before do
    Apify.reset!
    Apify.configure do |apify_config|
      apify_config.api_token = "test-apify-token"
      apify_config.max_retries = 0
      apify_config.sleep_fn = ->(_seconds) {}
    end
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# frozen_string_literal: true

module ApifyHelpers
  API_BASE = "https://api.apify.com/v2"
  ACTOR_ID = "dev_fusion~linkedin-profile-scraper"

  def sync_dataset_items_url(actor_id = ACTOR_ID, timeout: nil)
    url = "#{API_BASE}/actors/#{actor_id}/run-sync-get-dataset-items"
    return url if timeout.nil?

    "#{url}?timeout=#{Integer(timeout)}"
  end

  def stub_sync_dataset_items_success(body:, actor_id: ACTOR_ID, timeout: nil)
    stub_request(:post, sync_dataset_items_url(actor_id, timeout: timeout))
      .with(headers: { "Authorization" => "Bearer test-apify-token" })
      .to_return(status: 200, body: body)
  end

  def stub_sync_dataset_items_error(status:, body:, actor_id: ACTOR_ID, timeout: nil)
    stub_request(:post, sync_dataset_items_url(actor_id, timeout: timeout))
      .with(headers: { "Authorization" => "Bearer test-apify-token" })
      .to_return(status: status, body: body)
  end
end

RSpec.configure do |config|
  config.include ApifyHelpers
end

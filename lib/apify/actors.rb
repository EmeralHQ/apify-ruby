# frozen_string_literal: true

module Apify
  class Actors
    def initialize(client)
      @client = client
    end

    def run_sync_get_dataset_items(actor_id:, input:, read_timeout: nil, run_timeout_secs: nil)
      @client.post_sync_dataset_items(
        actor_id,
        input,
        read_timeout: read_timeout,
        run_timeout_secs: run_timeout_secs
      )
    end
  end
end

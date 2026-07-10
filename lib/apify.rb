# frozen_string_literal: true

require_relative "apify/version"

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.setup

require_relative "apify/error"

module Apify
  class << self
    def configure(&)
      Config.configure(&)
    end

    def config
      Config.config
    end

    def client
      @client ||= Client.new
    end

    def actors
      @actors ||= Actors.new(client)
    end

    def reset!
      @client = nil
      @actors = nil
    end
  end
end

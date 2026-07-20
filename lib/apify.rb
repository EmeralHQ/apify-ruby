# frozen_string_literal: true

require_relative "apify/version"

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/apify/version.rb")
loader.setup

require_relative "apify/error"

module Apify
  class << self
    # Non-reentrant Mutex: `actors` must not call the public `client` method
    # from inside the lock (that would deadlock), so it builds @client itself.
    LOCK = Mutex.new
    private_constant :LOCK

    def configure(&)
      Config.configure(&)
    end

    def config
      Config.config
    end

    def client
      LOCK.synchronize { @client ||= Client.new }
    end

    def actors
      LOCK.synchronize { @actors ||= Actors.new(@client ||= Client.new) }
    end

    def reset!
      LOCK.synchronize do
        @client = nil
        @actors = nil
      end
    end
  end
end

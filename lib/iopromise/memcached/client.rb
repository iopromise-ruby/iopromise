# frozen_string_literal: true

require 'memcached'
require_relative 'promise'

module IOPromise
  module Memcached
    class Client
      def initialize(*args, **kwargs)
        @client = ::Memcached::Client.new(*args, **kwargs)
      end

      def get_as_promise(key)
        MemcachePromise.new(@client, key)
      end
    end
  end
end

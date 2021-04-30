# frozen_string_literal: true

require 'memcached'
require_relative 'promise'

module IOPromise
  module Memcached
    class Client
      def initialize(*args, **kwargs)
        if args.first.is_a?(::Memcached::Client)
          @client = args.first.clone
        else
          @client = ::Memcached::Client.new(*args, **kwargs)
        end
      end

      def get_as_promise(key)
        MemcachePromise.new(@client, key)
      end
    end
  end
end

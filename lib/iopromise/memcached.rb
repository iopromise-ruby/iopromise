# frozen_string_literal: true

require_relative 'memcached/client'

module IOPromise
  module Memcached
    class << self
      def new(*args, **kwargs)
        ::IOPromise::Memcached::Client.new(*args, **kwargs)
      end
    end
  end
end

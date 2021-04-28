# frozen_string_literal: true

require 'faraday'

require_relative 'promise'

module IOPromise
  module Faraday
    class Connection < ::Faraday::Connection
      def with_deferred_parallel
        @parallel_manager = FaradayPromise.parallel_manager
        yield
      ensure
        @parallel_manager = nil
      end
      
      def get_as_promise(*args, **kwargs)
        @parallel_manager = FaradayPromise.parallel_manager
        FaradayPromise.new(get(*args, **kwargs))
      ensure
        @parallel_manager = nil
      end
    end
  end
end

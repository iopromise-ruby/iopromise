# frozen_string_literal: true

require_relative 'executor_pool'

module IOPromise
  module Memcached
    class MemcachePromise < ::IOPromise::Base
      attr_reader :key

      def initialize(client = nil, key = nil)
        super()
    
        @client = client
        @key = key
    
        ::IOPromise::ExecutorContext.current.register(self) unless @client.nil? || @key.nil?
      end
    
      def wait
        if @client.nil? || @key.nil?
          super
        else
          ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
        end
      end
    
      def execute_pool
        MemcacheExecutorPool.for(@client)
      end
    end
  end
end

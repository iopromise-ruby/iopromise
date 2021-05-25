# frozen_string_literal: true

require_relative 'executor_pool'

module IOPromise
  module Dalli
    class DalliPromise < ::IOPromise::Base
      attr_reader :key

      def initialize(server = nil, key = nil)
        super()
    
        @server = server
        @key = key
    
        ::IOPromise::ExecutorContext.current.register(self) unless @server.nil? || @key.nil?
      end
    
      def wait
        if @server.nil? || @key.nil?
          super
        else
          ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
        end
      end
    
      def execute_pool
        DalliExecutorPool.for(@server)
      end
    end
  end
end

# frozen_string_literal: true

require 'promise'

require_relative 'executor_pool'

module IOPromise
  module Deferred
    class DeferredPromise < ::Promise
      def initialize(&block)
        super()
    
        @block = block
    
        ::IOPromise::ExecutorContext.current.register(self)
      end
    
      def wait
        ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
      end
    
      def execute_pool
        DeferredExecutorPool.for(Thread.current)
      end

      def run_deferred
        begin
          fulfill(@block.call)
        rescue => exception
          reject(exception)
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'executor_pool'

module IOPromise
  module Deferred
    class DeferredPromise < ::IOPromise::Base
      def initialize(&block)
        super()
    
        @block = block
    
        ::IOPromise::ExecutorContext.current.register(self) unless @block.nil?
      end
    
      def wait
        if @block.nil?
          super
        else
          ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
        end
      end
    
      def execute_pool
        DeferredExecutorPool.for(Thread.current)
      end

      def run_deferred
        return if @block.nil? || !pending?
        begin
          fulfill(@block.call)
        rescue => exception
          reject(exception)
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'executor_pool'

module IOPromise
  module Deferred
    class DeferredPromise < ::IOPromise::Base
      def initialize(timeout = nil, &block)
        super()
    
        @block = block
        
        unless timeout.nil?
          @defer_until = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        end
    
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

      def time_until_execution
        return 0 unless defined?(@defer_until)

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return 0 if now > @defer_until

        @defer_until - now
      end
    end
  end
end

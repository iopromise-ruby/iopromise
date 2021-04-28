# frozen_string_literal: true

require 'promise'

require_relative 'continuable_hydra'
require_relative 'executor_pool'

module IOPromise
  module Faraday
    class FaradayPromise < ::Promise
      def self.parallel_manager
        ContinuableHydra.for_current_thread
      end
    
      def initialize(response = nil)
        super()
    
        @response = response
        @started = false
    
        unless @response.nil?
          @response.on_complete do |response_env|
            fulfill(@response)
            execute_pool.complete(self)
          end
        end
    
        ::IOPromise::ExecutorContext.current.register(self) unless @response.nil?
      end
    
      def wait
        ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_fulfilled: self)
      end
    
      def execute_pool
        FaradayExecutorPool.for(Thread.current)
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'continuable_hydra'
require_relative 'executor_pool'

module IOPromise
  module Faraday
    class FaradayPromise < ::IOPromise::Base
      def self.parallel_manager
        ContinuableHydra.for_current_thread
      end
    
      def initialize(response = nil)
        super()
    
        @response = response
        @started = false

        # mark as starting immediately, ideally we would trigger this once the request is
        # actually dequeued from the hydra into the multi_socket.
        execute_pool.begin_executing(self)
    
        unless @response.nil?
          @response.on_complete do |response_env|
            fulfill(@response)
            execute_pool.complete(self)
          end
        end
    
        ::IOPromise::ExecutorContext.current.register(self) unless @response.nil?
      end
    
      def wait
        if @response.nil?
          super
        else
          ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
        end
      end
    
      def execute_pool
        FaradayExecutorPool.for(Thread.current)
      end
    end
  end
end

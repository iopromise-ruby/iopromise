# frozen_string_literal: true

require_relative 'executor_pool'

module IOPromise
  module Dalli
    class DalliPromise < ::IOPromise::Base
      attr_reader :key

      def initialize(server = nil, key = nil)
        super()

        # when created from a 'then' call, initialize nothing
        return if server.nil? || key.nil?

        @server = server
        @key = key
        @start_time = nil
        
        ::IOPromise::ExecutorContext.current.register(self)
      end
    
      def wait
        unless defined?(@server)
          super
        else
          ::IOPromise::ExecutorContext.current.wait_for_all_data(end_when_complete: self)
        end
      end
    
      def execute_pool
        return @pool if defined?(@pool)
        if defined?(@server)
          @pool = DalliExecutorPool.for(@server)
        else
          @pool = nil
        end
      end

      def in_select_loop
        if @start_time.nil?
          @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      def timeout_remaining
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        elapsed = now - @start_time
        remaining = @server.options[:socket_timeout] - elapsed
        return 0 if remaining < 0
        remaining
      end

      def timeout?
        return false if @start_time.nil?
        timeout_remaining <= 0
      end
    end
  end
end

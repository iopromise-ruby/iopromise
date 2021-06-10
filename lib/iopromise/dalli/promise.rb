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
        @start_time = nil
    
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
        return @pool if defined? @pool
        @pool = DalliExecutorPool.for(@server)
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

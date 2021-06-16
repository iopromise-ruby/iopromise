# frozen_string_literal: true

require_relative 'continuable_hydra'

module IOPromise
  module Faraday
    class FaradayExecutorPool < IOPromise::ExecutorPool::Base
      def initialize(*)
        super

        @hydra = ContinuableHydra.for_current_thread
        @hydra.iop_handler = self

        @monitors = {}
      end

      def monitor_add(io)
        @monitors[io] = ::IOPromise::ExecutorContext.current.register_observer_io(self, io, :r)
      end

      def monitor_remove(io)
        monitor = @monitors.delete(io)
        monitor.close unless monitor.nil?
      end

      def set_interests(io, interest)
        monitor = @monitors[io]
        monitor.interests = interest unless monitor.nil?
      end

      def set_timeout(timeout)
        self.select_timeout = timeout
      end

      def monitor_ready(monitor, readiness)
        @hydra.socket_is_ready(monitor.io, monitor.readable?, monitor.writable?)
      end

      def execute_continue
        # mark all pending promises as executing since they could be started any time now.
        # ideally we would do this on dequeue.
        @pending.each do |promise|
          begin_executing(promise) unless promise.started_executing?
        end

        @hydra.execute_continue
      end
    end
  end
end

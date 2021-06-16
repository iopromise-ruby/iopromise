# frozen_string_literal: true

module IOPromise
  module Dalli
    class DalliExecutorPool < IOPromise::ExecutorPool::Base
      def initialize(*)
        super

        @iop_monitor = nil
      end

      def dalli_server
        @connection_pool
      end

      def execute_continue
        dalli_server.execute_continue
      end

      def connected_socket(sock)
        close_socket

        @iop_monitor = ::IOPromise::ExecutorContext.current.register_observer_io(self, sock, :r)
      end

      def close_socket
        unless @iop_monitor.nil?
          @iop_monitor.close
          @iop_monitor = nil
        end
      end

      def monitor_ready(monitor, readiness)
        dalli_server.async_io_ready(monitor.readable?, monitor.writable?)
      end

      def set_interest(direction, interested)
        if interested
          @iop_monitor.add_interest(direction)
        else
          @iop_monitor.remove_interest(direction)
        end
      end
    end
  end
end

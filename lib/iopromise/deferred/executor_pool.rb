# frozen_string_literal: true

module IOPromise
  module Deferred
    class DeferredExecutorPool < ::IOPromise::ExecutorPool::Batch
      def initialize(*)
        super

        # register a dummy reader that never fires, to indicate to the event loop that
        # there is a valid, active ExecutorPool.
        @pipe_rd, @pipe_wr = IO.pipe
        @iop_monitor = ::IOPromise::ExecutorContext.current.register_observer_io(self, @pipe_rd, :r)
      end

      def execute_continue
        if @current_batch.empty?
          next_batch
        end

        # we are just running this in the sync cycle, in a blocking way.
        timeouts = []
        @current_batch.each do |promise|
          time_until_execution = promise.time_until_execution
          if time_until_execution <= 0
            begin_executing(promise)
            promise.run_deferred
          else
            timeouts << time_until_execution
          end
        end

        if timeouts.empty?
          @select_timeout = nil
        else
          # ensure we get back to this loop not too long after 
          @select_timeout = timeouts.min
        end

        # we reset the batch - the promises that are not completed will still be
        # pending and will be available next time we are called.
        @current_batch = []
      end
    end
  end
end

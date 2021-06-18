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

        until @current_batch.empty?
          # we are just running this in the sync cycle, in a blocking way.
          @current_batch.each do |promise|
            begin_executing(promise)
            promise.run_deferred
          end

          @current_batch = []

          next_batch
        end

        # we always fully complete each cycle
      end
    end
  end
end

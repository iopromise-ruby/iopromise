# frozen_string_literal: true

require_relative 'continuable_hydra'

module IOPromise
  module Faraday
    class FaradayExecutorPool < IOPromise::ExecutorPool::Base
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        # mark all pending promises as executing since they could be started any time now.
        # ideally we would do this on dequeue.
        @pending.each do |promise|
          begin_executing(promise) unless promise.started_executing?
        end

        ContinuableHydra.for_current_thread.execute_continue(ready_readers, ready_writers, ready_exceptions)
      end
    end
  end
end

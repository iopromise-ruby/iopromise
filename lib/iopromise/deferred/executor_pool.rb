# frozen_string_literal: true

module IOPromise
  module Deferred
    class DeferredExecutorPool < IOPromise::ExecutorPool::Batch
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        if @current_batch.empty?
          next_batch
        end

        # we are just running this in the sync cycle, in a blocking way.
        @current_batch.each do |promise|
          promise.run_deferred
          complete(promise)
        end

        @current_batch = []

        # we always fully complete each cycle
        return [[], [], [], nil]
      end
    end
  end
end

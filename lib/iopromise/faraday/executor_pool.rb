# frozen_string_literal: true

require_relative 'continuable_hydra'

module IOPromise
  module Faraday
    class FaradayExecutorPool < IOPromise::ExecutorPool::Base
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        ContinuableHydra.for_current_thread.execute_continue(ready_readers, ready_writers, ready_exceptions)
      end
    end
  end
end

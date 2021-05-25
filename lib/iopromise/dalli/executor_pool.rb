# frozen_string_literal: true

module IOPromise
  module Dalli
    class DalliExecutorPool < IOPromise::ExecutorPool::Base
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        dalli_server = @connection_pool

        dalli_server.execute_continue(ready_readers, ready_writers, ready_exceptions)
      end
    end
  end
end

# frozen_string_literal: true

module IOPromise
  module ExecutorPool
    class Base
      class << self
        def for(connection_pool)
          @executors ||= {}
          @executors[connection_pool] ||= new(connection_pool)
        end
      end
    
      def initialize(connection_pool)
        @connection_pool = connection_pool
        @pending = []
      end
    
      def register(item)
        @pending << item
      end

      def complete(item)
        @pending.delete(item)
      end

      # Continue execution of one or more pending IOPromises assigned to this pool.
      # Returns [readers, writers, exceptions, max_timeout], which are arrays of the
      # readers, writers, and exceptions to select on. The timeout specifies the maximum
      # time to block waiting for one of these IO objects to become ready, after which
      # this function is called again with empty "ready" arguments.
      # Must be implemented by subclasses.
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        raise NotImplementedError
      end
    
      def sync
        @pending.each do |promise|
          promise.sync if promise.is_a?(Promise)
        end
      end
    end
  end
end

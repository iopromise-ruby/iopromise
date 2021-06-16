# frozen_string_literal: true

require 'promise/observer'

module IOPromise
  module ExecutorPool
    class Base
      include Promise::Observer

      class << self
        def for(connection_pool)
          @executors ||= {}
          @executors[connection_pool] ||= new(connection_pool)
        end
      end

      attr_accessor :select_timeout
    
      def initialize(connection_pool)
        @connection_pool = connection_pool
        @pending = []

        @monitors = {}

        @select_timeout = nil
      end
    
      def register(item)
        @pending << item
        item.subscribe(self, item, item)
      end

      def promise_fulfilled(_value, item)
        @pending.delete(item)
      end
      def promise_rejected(_reason, item)
        @pending.delete(item)
      end

      def begin_executing(item)
        item.beginning
      end

      # Continue execution of one or more pending IOPromises assigned to this pool.
      # Implementations may choose to pre-register IO handled using:
      #   ExecutorContext.current.register_observer_io(...)
      # Alternatively, they can be registered when this function is called.
      # During this function, implementations should check for timeouts and run
      # any housekeeping operations.
      #
      # Must be implemented by subclasses.
      def execute_continue
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

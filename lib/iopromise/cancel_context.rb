# frozen_string_literal: true

module IOPromise
  class CancelContext
    class << self
      def context_stack
        Thread.current[:iopromise_context_stack] ||= []
      end

      def current
        context_stack.last
      end

      def push
        new_ctx = CancelContext.new(current)
        context_stack.push(new_ctx)
        new_ctx
      end

      def pop
        ctx = context_stack.pop
        ctx.cancel
        ctx
      end

      def with_new_context
        ctx = push
        yield ctx
      ensure
        pop
      end
    end

    def initialize(parent)
      parent.subscribe(self) unless parent.nil?
    end

    def subscribe(observer)
      @observers ||= []
      @observers.push observer
    end

    def cancel
      return unless defined?(@observers)
      @observers.each do |o|
        o.cancel
      end
      @observers = []
    end
  end
end

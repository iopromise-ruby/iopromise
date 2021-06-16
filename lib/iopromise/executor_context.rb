# frozen_string_literal: true

require 'set'
require 'nio'

module IOPromise
  class ExecutorContext
    class << self
      def current
        @context ||= ExecutorContext.new
      end
    end

    def initialize
      @pools = {}

      @pending_registrations = []

      @selector = NIO::Selector.new

      super
    end

    def register_observer_io(observer, io, interest)
      monitor = @selector.register(io, interest)
      monitor.value = observer
      monitor
    end

    def cancel_pending
      # not yet implemented, but would be a good thing to support
    end

    def register(promise)
      @pending_registrations << promise
    end

    def wait_for_all_data(end_when_complete: nil)
      loop do
        complete_pending_registrations

        @pools.each do |pool, _|
          pool.execute_continue
        end
        
        unless end_when_complete.nil?
          return unless end_when_complete.pending?
        end
        
        break if @selector.empty?

        # if we have any pending promises to register, we'll not block at all so we immediately continue
        unless @pending_registrations.empty?
          wait_time = 0
        else
          wait_time = nil
          @pools.each do |pool, _|
            timeout = pool.select_timeout
            wait_time = timeout if wait_time.nil? || (!timeout.nil? && timeout < wait_time)
          end
        end
        
        ready_count = select(wait_time)
      end

      unless end_when_complete.nil?
        raise ::IOPromise::Error.new('Internal error: IO loop completed without fulfilling the desired promise')
      else
        @pools.each do |pool, _|
          pool.wait
        end
      end
    ensure
      complete_pending_registrations
    end

    private

    def select(wait_time)
      @selector.select(wait_time) do |monitor|
        observer = monitor.value
        observer.monitor_ready(monitor, monitor.readiness)
      end
    end

    def complete_pending_registrations
      return if @pending_registrations.empty?
      pending = @pending_registrations
      @pending_registrations = []
      pending.each do |promise|
        register_now(promise)
      end
    end

    def register_now(promise)
      pool = promise.execute_pool
      pool.register(promise)
      @pools[pool] = true
    end
  end
end

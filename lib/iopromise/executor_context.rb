# frozen_string_literal: true

require 'set'

module IOPromise
  class ExecutorContext
    class << self
      def push
        @contexts ||= []
        @contexts << ExecutorContext.new
      end

      def current
        @contexts.last
      end

      def pop
        @contexts.pop
      end
    end

    def initialize
      @pools = Set.new

      @pool_ready_readers = {}
      @pool_ready_writers = {}
      @pool_ready_exceptions = {}

      @pending_registrations = []
    end

    def register(promise)
      @pending_registrations << promise
    end

    def wait_for_all_data(end_when_complete: nil)
      loop do
        complete_pending_registrations

        readers, writers, exceptions, wait_time = continue_to_read_pools

        unless end_when_complete.nil?
          return unless end_when_complete.pending?
        end

        break if readers.empty? && writers.empty? && exceptions.empty? && @pending_registrations.empty?

        # if we have any pending promises to register, we'll not block at all so we immediately continue
        wait_time = 0 unless @pending_registrations.empty?
  
        # we could be clever and decide which ones to "continue" on next
        ready = IO.select(readers.keys, writers.keys, exceptions.keys, wait_time)
        ready = [[], [], []] if ready.nil?
        ready_readers, ready_writers, ready_exceptions = ready

        # group by the pool object that provided the fd
        @pool_ready_readers = ready_readers.group_by { |i| readers[i] }
        @pool_ready_writers = ready_writers.group_by { |i| writers[i] }
        @pool_ready_exceptions = ready_exceptions.group_by { |i| exceptions[i] }
      end
  
      unless end_when_complete.nil?
        raise ::IOPromise::Error.new('Internal error: IO loop completed without fulfilling the desired promise')
      else
        @pools.each do |pool|
          pool.sync
        end
      end
    ensure
      complete_pending_registrations
    end

    private

    def complete_pending_registrations
      pending = @pending_registrations
      @pending_registrations = []
      pending.each do |promise|
        register_now(promise)
      end
    end

    def continue_to_read_pools
      readers = {}
      writers = {}
      exceptions = {}
      max_timeout = nil

      @pools.each do |pool|
        rd, wr, ex, ti = pool.execute_continue(@pool_ready_readers[pool], @pool_ready_writers[pool], @pool_ready_exceptions[pool])
        rd.each do |io|
          readers[io] = pool
        end
        wr.each do |io|
          writers[io] = pool
        end
        ex.each do |io|
          exceptions[io] = pool
        end
        if max_timeout.nil? || (!ti.nil? && ti < max_timeout)
          max_timeout = ti
        end
      end

      [readers, writers, exceptions, max_timeout]
    end

    def register_now(promise)
      pool = promise.execute_pool
      pool.register(promise)
      @pools.add(pool)
    end
  end
end

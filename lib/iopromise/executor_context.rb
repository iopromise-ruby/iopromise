
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
    end

    def register(continuation)
      pool = continuation.execute_pool
      pool.register(continuation)
      @pools.add(pool)
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
  
    def wait_for_all_data(end_when_fulfilled: nil)
      loop do
        readers, writers, exceptions, wait_time = continue_to_read_pools
        break if readers.empty? && writers.empty? && exceptions.empty?

        unless end_when_fulfilled.nil?
          return if end_when_fulfilled.fulfilled?
        end
  
        # we could be clever and decide which ones to "continue" on next
        ready = IO.select(readers.keys, writers.keys, exceptions.keys, wait_time)
        ready = [[], [], []] if ready.nil?
        ready_readers, ready_writers, ready_exceptions = ready

        # group by the pool object that provided the fd
        @pool_ready_readers = ready_readers.group_by { |i| readers[i] }
        @pool_ready_writers = ready_writers.group_by { |i| writers[i] }
        @pool_ready_exceptions = ready_exceptions.group_by { |i| exceptions[i] }
      end
  
      @pools.each do |pool|
        pool.sync
      end
    end
  end
end

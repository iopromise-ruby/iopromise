# frozen_string_literal: true

module IOPromise
  module Memcached
    class MemcacheExecutorPool < ::IOPromise::ExecutorPool::Batch
      def initialize(*)
        super

        @monitors = {}
      end

      def next_batch
        super

        unless @current_batch.empty?
          @keys_to_promises = @current_batch.group_by { |promise| promise.key }
          @current_batch.each { |promise| begin_executing(promise) }
          begin
            memcache_client.begin_get_multi(@keys_to_promises.keys)
          rescue => e
            @keys_to_promises.values.flatten.each do |promise|
              promise.reject(e)
              @current_batch.delete(promise)
            end

            @keys_to_promises = nil
          end
        end
      end

      def execute_continue
        if @current_batch.empty?
          next_batch
        end

        if @current_batch.empty?
          @monitors.each do |_, monitor|
            monitor.interests = nil
          end
          return
        end

        so_far, readers, writers = memcache_client.continue_get_multi

        # when we're done (nothing to wait on), fill in any remaining keys with nil for completions to occur
        if readers.empty? && writers.empty?
          @keys_to_promises.each do |key, _|
            so_far[key] = nil unless so_far.include? key
          end
        end

        so_far.each do |key, value|
          next unless @keys_to_promises[key]
          @keys_to_promises[key].each do |promise|
            next if promise.fulfilled?

            promise.fulfill(value)
            @current_batch.delete(promise)
          end
        end

        @monitors.each do |_, monitor|
          monitor.interests = nil
        end

        readers.each do |reader|
          @monitors[reader] ||= ::IOPromise::ExecutorContext.current.register_observer_io(self, reader, :r)
          @monitors[reader].add_interest(:r)
        end

        writers.each do |writer|
          @monitors[writer] ||= ::IOPromise::ExecutorContext.current.register_observer_io(self, writer, :w)
          @monitors[writer].add_interest(:w)
        end
      end

      def memcache_client
        @connection_pool
      end
    end
  end
end

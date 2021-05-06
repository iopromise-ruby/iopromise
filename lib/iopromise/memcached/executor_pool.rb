# frozen_string_literal: true

module IOPromise
  module Memcached
    class MemcacheExecutorPool < ::IOPromise::ExecutorPool::Batch
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
              complete(promise)
              @current_batch.delete(promise)
            end

            @keys_to_promises = nil
          end
        end
      end

      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        if @current_batch.empty?
          next_batch
        end

        return [[], [], [], nil] if @current_batch.empty?

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
            complete(promise)
            @current_batch.delete(promise)
          end
        end

        [readers, writers, [], nil]
      end

      def memcache_client
        @connection_pool
      end
    end
  end
end

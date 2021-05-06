# frozen_string_literal: true

module IOPromise
  module ExecutorPool
    class Batch < Base
      def initialize(connection_pool)
        super(connection_pool)
    
        @current_batch = []
      end
    
      def next_batch
        # ensure that all current items are fully completed
        @current_batch.each do |promise|
          promise.wait
        end
        
        # every pending operation becomes part of the current batch
        @current_batch = @pending.dup
      end
    end
  end
end

# frozen_string_literal: true

module IOPromise
  module ExecutorPool
    class Batch < Base
      def initialize(*)
        super
    
        @current_batch = []
      end
    
      def next_batch
        # ensure that all current items are fully completed
        @current_batch.each do |promise|
          promise.wait
        end
        
        # every pending operation becomes part of the current batch
        # we don't include promises with a source set, because that
        # indicates that they depend on another promise now.
        @current_batch = @pending.select { |p| p.pending? && p.source.nil? }
      end
    end
  end
end

# frozen_string_literal: true

require 'typhoeus'
require_relative 'multi_socket_action'

module IOPromise
  module Faraday
    class ContinuableHydra < Typhoeus::Hydra
      class << self
        def for_current_thread
          Thread.current[:faraday_promise_typhoeus_hydra] ||= new
        end
      end
    
      def initialize(options = {})
        super(options)
        
        @multi = MultiSocketAction.new(options.reject{|k,_| k==:max_concurrency})
      end
    
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        # fill up the curl easy handle as much as possible
        dequeue_many
    
        @multi.execute_continue(ready_readers, ready_writers, ready_exceptions)
      end
    end
  end
end

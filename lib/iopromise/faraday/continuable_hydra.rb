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

      def iop_handler=(iop_handler)
        @multi.iop_handler = iop_handler
      end

      def socket_is_ready(io, readable, writable)
        @multi.socket_is_ready(io, readable, writable)
      end
    
      def execute_continue
        # fill up the curl easy handle as much as possible
        dequeue_many
    
        @multi.execute_continue
      end
    end
  end
end

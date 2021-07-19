# frozen_string_literal: true

require_relative 'deferred/promise'

module IOPromise
  module Deferred
    class << self
      def new(*args, **kwargs, &block)
        ::IOPromise::Deferred::DeferredPromise.new(*args, **kwargs, &block)
      end
    end
  end
end

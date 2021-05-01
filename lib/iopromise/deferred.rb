# frozen_string_literal: true

require_relative 'deferred/promise'

module IOPromise
  module Deferred
    class << self
      def new(&block)
        ::IOPromise::Deferred::DeferredPromise.new(&block)
      end
    end
  end
end

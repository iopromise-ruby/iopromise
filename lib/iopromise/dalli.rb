# frozen_string_literal: true

require_relative 'dalli/client'

module IOPromise
  module Dalli
    class << self
      def new(*args, **kwargs)
        ::IOPromise::Dalli::Client.new(*args, **kwargs)
      end
    end
  end
end

# frozen_string_literal: true

module IOPromise
  module Dalli
    class Response
      attr_reader :key, :value, :cas

      def initialize(key:, value:, exists: false, stored: false, cas: nil)
        @key = key
        @value = value
        @exists = exists
        @stored = stored
        @cas = cas
      end

      def exist?
        @exists
      end

      def stored?
        @stored
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'faraday/connection'

module IOPromise
  module Faraday
    class << self
      def new(url = nil, options = {}, &block)
        options = ::Faraday.default_connection_options.merge(options)
        ::IOPromise::Faraday::Connection.new(url, options) do |faraday|
          faraday.adapter :typhoeus
          block.call unless block.nil?
        end
      end
    end
  end
end

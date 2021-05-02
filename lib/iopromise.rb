# frozen_string_literal: true

require "promise"

require_relative "iopromise/version"

require_relative "iopromise/executor_context"
require_relative "iopromise/executor_pool/base"
require_relative "iopromise/executor_pool/batch"
require_relative "iopromise/executor_pool/sequential"

module IOPromise
  class Error < StandardError; end

  class Base < ::Promise
    def initialize(*)
      @instrument_begin = []
      @instrument_end = []
      
      super
    end

    def instrument(begin_cb = nil, end_cb = nil)
      @instrument_begin << begin_cb unless begin_cb.nil?
      @instrument_end << end_cb unless end_cb.nil?
    end

    def beginning
      @instrument_begin.each { |cb| cb.call(self) }
    end

    def fulfill(value)
      @instrument_end.each { |cb| cb.call(self) }
      super(value)
    end

    def reject(reason)
      @instrument_end.each { |cb| cb.call(self) }
      super(reason)
    end
  end
end

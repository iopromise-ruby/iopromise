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
      @started_executing = false
      
      super
    end

    def instrument(begin_cb = nil, end_cb = nil)
      raise ::IOPromise::Error.new("Instrumentation called after promise already started executing") if @started_executing
      @instrument_begin << begin_cb unless begin_cb.nil?
      @instrument_end << end_cb unless end_cb.nil?
    end

    def beginning
      @instrument_begin.each { |cb| cb.call(self) }
      @started_executing = true
    end

    def started_executing?
      @started_executing
    end

    def notify_completion
      @instrument_end.each { |cb| cb.call(self) }
      @instrument_end = []
    end

    def fulfill(value)
      notify_completion
      super(value)
    end

    def reject(reason)
      notify_completion
      super(reason)
    end
  end
end

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
    def instrument(begin_cb = nil, end_cb = nil)
      raise ::IOPromise::Error.new("Instrumentation called after promise already started executing") if started_executing?
      unless begin_cb.nil?
        @instrument_begin ||= []
        @instrument_begin << begin_cb
      end
      unless end_cb.nil?
        @instrument_end ||= []
        @instrument_end << end_cb
      end
    end

    def beginning
      @instrument_begin&.each { |cb| cb.call(self) }
      @instrument_begin&.clear
      @started_executing = true
    end

    def started_executing?
      !!@started_executing
    end

    def notify_completion(value: nil, reason: nil)
      @instrument_end&.each { |cb| cb.call(self, value: value, reason: reason) }
      @instrument_end&.clear
    end

    def fulfill(value)
      notify_completion(value: value)
      super(value)
    end

    def reject(reason)
      notify_completion(reason: reason)
      super(reason)
    end
  end
end

# frozen_string_literal: true

require_relative "iopromise/version"

require_relative "iopromise/executor_context"
require_relative "iopromise/executor_pool/base"
require_relative "iopromise/executor_pool/batch"
require_relative "iopromise/executor_pool/sequential"

module IOPromise
  class Error < StandardError; end
end

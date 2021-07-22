# frozen_string_literal: true

require 'iopromise'

module IOPromise
  module Rack
    class ContextMiddleware
      def initialize(app)
        @app = app
      end
    
      def call(env)
        IOPromise::CancelContext.with_new_context do
          @app.call(env)
        end
      end
    end
  end
end

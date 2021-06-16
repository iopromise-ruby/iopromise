
module IOPromise
  module Rack
    class ContextMiddleware
      def initialize(app)
        @app = app
      end
    
      def call(env)
        begin
          status, headers, body = @app.call(env)
        ensure
          ::IOPromise::ExecutorContext.current.cancel_pending
        end
        [status, headers, body]
      end
    end
  end
end

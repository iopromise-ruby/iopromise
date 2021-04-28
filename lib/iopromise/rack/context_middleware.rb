
module IOPromise
  module Rack
    class ContextMiddleware
      def initialize(app)
        @app = app
      end
    
      def call(env)
        ::IOPromise::ExecutorContext.push
        begin
          status, headers, body = @app.call(env)
        ensure
          ::IOPromise::ExecutorContext.pop
        end
        [status, headers, body]
      end
    end
  end
end

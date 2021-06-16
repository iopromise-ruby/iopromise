# frozen_string_literal: true

module IOPromise
  module ExecutorPool
    class Sequential < Base
      def execute_continue_item(item)
        item.execute_continue
      end
    
      def execute_continue
        @pending.dup.each do |active|
          execute_continue_item(active)
          
          unless active.fulfilled?
            # once we're waiting on our one next item, we're done
            return
          end
        end
    
        # if we fall through to here, we have nothing to wait on.
      end
    end
  end
end

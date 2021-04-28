
module IOPromise
  module ExecutorPool
    class Sequential < Base
      def execute_continue_item(item, ready_readers, ready_writers, ready_exceptions)
        item.execute_continue(ready_readers, ready_writers, ready_exceptions)
      end
    
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        @pending.dup.each do |active|
          status = if active.fulfilled?
            nil
          else
            execute_continue_item(active, ready_readers, ready_writers, ready_exceptions)
          end
          
          unless status.nil?
            # once we're waiting on our one next item, we're done
            return status
          else
            # we're done with this one, so remove it
            complete(active)
          end
        end
    
        # if we fall through to here, we have nothing to wait on.
        [[], [], [], nil]
      end
    end
  end
end

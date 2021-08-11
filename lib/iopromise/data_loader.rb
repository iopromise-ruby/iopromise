# frozen_string_literal: true

module IOPromise
  module DataLoader
    module ClassMethods
      def attr_async(attr_name, build_func = nil)
        @promised_data_keys ||= []
        @promised_data_keys << attr_name

        if build_func.nil?
          self.class_eval("def async_#{attr_name};@#{attr_name};end")
        else
          self.define_method("async_#{attr_name}") do
            @promised_data_memo ||= {}
            @promised_data_memo[attr_name] ||= self.instance_exec(&build_func)
          end
        end

        self.class_eval("def #{attr_name};async_#{attr_name}.sync;end")
      end
  
      def promised_data_keys
        @promised_data_keys ||= []
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def data_promises
      self.class.promised_data_keys.flat_map do |k|
        p = send("async_#{k}")
        case p
        when ::IOPromise::DataLoader
          # greedily, recursively preload all nested data that we know about immediately
          p.data_promises
        when ::Promise
          # allow nesting of dataloaders chained behind other promises
          resolved = p.then do |result|
            if result.is_a?(::IOPromise::DataLoader)
              # likewise, if we resolved a promise that we can recurse, load that data too.
              result.data_as_promise
            else
              result
            end
          end

          [resolved]
        else
          raise TypeError.new("Instance variable #{k.to_s} used with attr_async but was not a promise or a IOPromise::DataLoader.")
        end
      end
    end

    def data_as_promise
      @data_as_promise ||= Promise.all(data_promises)
    end

    def sync
      data_as_promise.sync
      self
    end
  end
end

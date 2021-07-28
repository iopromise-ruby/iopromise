# frozen_string_literal: true

module IOPromise
  module DataLoader
    module ClassMethods
      def attr_promised_data(*args)
        build_func = if args.last&.is_a?(Proc)
          args.pop
        else
          nil
        end

        @promised_data_keys ||= []
        @promised_data_keys.concat(args)

        args.each do |arg|
          if build_func.nil?
            self.class_eval("def #{arg}_promise;@#{arg};end")
          else
            self.define_method("#{arg}_promise") do
              @promised_data_memo ||= {}
              @promised_data_memo[arg] ||= if build_func.arity == 1
                self.instance_exec(arg, &build_func)
              else
                self.instance_exec(&build_func)
              end
            end
          end

          self.class_eval("def #{arg};#{arg}_promise.sync;end")
        end
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
        p = send("#{k}_promise")
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
          raise TypeError.new("Instance variable #{k.to_s} used with attr_promised_data but was not a promise or a IOPromise::DataLoader.")
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

# frozen_string_literal: true

module IOPromise
  module DataLoader
    module ClassMethods
      def attr_async(attr_name, build_func_or_options = nil)
        self.attr_async_names << attr_name

        if build_func_or_options.nil?
          self.class_eval("def async_#{attr_name};@#{attr_name};end")
        else
          if build_func_or_options.is_a?(Hash)
            # attr_async :something, after: [:foo, :bar], then: -> { ... }
            build_func = build_func_or_options[:then]
            after = build_func_or_options[:after]
          else
            # attr_async :something, -> { ... }
            build_func = build_func_or_options
            after = nil
          end

          self.define_method("async_#{attr_name}") do
            @attr_async_memo ||= {}
            @attr_async_memo[attr_name] ||= begin
              after_promise = if after.nil?
                Promise.resolve # immediate, nothing to wait on
              else
                dependencies = Array(after).map { |dep_attr_name| send("async_#{dep_attr_name}") }
                Promise.all(dependencies)
              end

              after_promise.then do # ensures this is always wrapped in a promise, and errors are captured
                self.instance_exec(&build_func)
              end
            end
          end
        end

        self.class_eval("def #{attr_name};async_#{attr_name}.sync;end")
      end
  
      def attr_async_names
        @attr_async_names ||= []
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def async_attributes
      @async_attributes ||= Promise.all(attr_async_promises)
    end

    def sync
      async_attributes.sync
      self
    end

    protected
    def attr_async_promises
      self.class.attr_async_names.flat_map do |k|
        p = send("async_#{k}")
        case p
        when ::IOPromise::DataLoader
          # greedily, recursively preload all nested data that we know about immediately
          p.attr_async_promises
        when ::Promise
          # allow nesting of dataloaders chained behind other promises
          resolved = p.then do |result|
            if result.is_a?(::IOPromise::DataLoader)
              # likewise, if we resolved a promise that we can recurse, load that data too.
              result.async_attributes
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
  end
end

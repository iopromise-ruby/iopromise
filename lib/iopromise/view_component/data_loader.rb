# frozen_string_literal: true

require "view_component/engine"

module IOPromise
  module ViewComponent
    module DataLoader
      module ClassMethods
        def attr_promised_data(*args)
          @promised_data ||= []
          @promised_data.concat(args)

          args.each do |arg|
            self.class_eval("def #{arg};@#{arg}.sync;end")
          end
        end
    
        def promised_data_keys
          @promised_data ||= []
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end

      def data_as_promise
        @data_promise ||= begin
          promises = self.class.promised_data_keys.map do |k|
            p = instance_variable_get('@' + k.to_s)
            if p.is_a?(IOPromise::ViewComponent::DataLoader)
              # recursively preload all nested data
              p.data_as_promise
            else
              # for any local promises, we'll unwrap them before completing
              p.then do |result|
                if result.is_a?(IOPromise::ViewComponent::DataLoader)
                  # likewise, if we resolved a promise that we can recurse, load that data too.
                  result.data_as_promise
                else
                  result
                end
              end
            end
          end

          Promise.all(promises)
        end
      end

      def sync
        data_as_promise.sync
      end

      def render_in(*)
        sync
        super
      end
    end
  end
end

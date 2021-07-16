# frozen_string_literal: true

require_relative "../data_loader"
require "view_component/engine"

module IOPromise
  module ViewComponent
    module DataLoader
      include ::IOPromise::DataLoader

      def self.included(base)
        base.extend(::IOPromise::DataLoader::ClassMethods)
      end

      def render_in(*)
        sync
        super
      end
    end
  end
end

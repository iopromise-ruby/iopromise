# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in iopromise.gemspec
gemspec

gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

group :development, :test do
  # faraday adapter
  gem 'faraday'
  gem 'typhoeus'

  # memcached adapter
  gem 'memcached', :git => 'https://github.com/theojulienne/memcached.git', :branch => 'continuable-get'

  # dalli adapter
  gem 'dalli', "= 2.7.11"

  # view_component extensions
  gem "rails"
  gem "view_component", require: "view_component/engine"
end

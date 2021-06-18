# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in iopromise.gemspec
gemspec

gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

group :development, :test do
  # view_component extensions
  gem "rails"
  gem "view_component", require: "view_component/engine"

  # benchmarking
  gem "benchmark-ips"
  gem "stackprof"
end

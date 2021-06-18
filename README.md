# IOPromise

IOPromise is a pattern that allows parallel execution of IO-bound requests (data store and RPCs) behind the abstraction of promises, without needing to introduce the complexity of threading. It uses [promise.rb](https://github.com/lgierth/promise.rb) for promises, and [nio4r](https://github.com/socketry/nio4r) to implement the IO loop.

A simple example of this behaviour is using [iopromise-faraday](https://github.com/iopromise-ruby/iopromise-faraday) to perform concurrent HTTP requests:
```ruby
require 'iopromise/faraday'

conn = IOPromise::Faraday.new('https://github.com/')

promises = (1..3).map do
  conn.get('/status')
end

Promise.all(promises).then do |responses|
  responses.each_with_index do |response, i|
    puts "#{i}: #{response.body.strip} #{response.headers["x-github-request-id"]}"
  end
end.sync
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'iopromise'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install iopromise

## Usage

IOPromise itself is a base library that makes it easy to wrap other IO-based workloads inside a promise-based API that back to an event loop. To use IOPromise, look at the following gems:

 * [iopromise-faraday](https://github.com/iopromise-ruby/iopromise-faraday) supports [faraday](https://github.com/lostisland/faraday) HTTP requests, backed by libcurl/ethon/typhoeus.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/theojulienne/iopromise. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/theojulienne/iopromise/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the iopromise project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/theojulienne/iopromise/blob/main/CODE_OF_CONDUCT.md).

# frozen_string_literal: true

require 'dalli'
require_relative 'promise'
require_relative 'patch_dalli'

module IOPromise
  module Dalli
    class Client
      # General note:
      # There is no need for explicit get_multi or batching, as requests
      # are sent as soon as the IOPromise is created, multiple can be
      # awaiting response at any time, and responses are automatically demuxed.
      def initialize(servers = nil, options = {})
        @cache_nils = !!options[:cache_nils]
        options[:iopromise_async] = true
        @options = options
        @client = ::Dalli::Client.new(servers, options)
      end

      # Returns a promise that resolves to a IOPromise::Dalli::Response with the
      # value for the given key, or +nil+ if the key is not found.
      def get(key, options = nil)
        execute_as_promise(:get, key, options)
      end

      # Convenience function that attempts to fetch the given key, or set
      # the key with a dynamically generated value if it does not exist.
      # Either way, the returned promise will resolve to the cached or computed
      # value.
      #
      # If the value does not exist then the provided block is run to generate
      # the value (which can also be a promise), after which the value is set
      # if it still doesn't exist.
      def fetch(key, ttl = nil, options = nil, &block)
        # match the Dalli behaviour exactly
        options = options.nil? ? ::Dalli::Client::CACHE_NILS : options.merge(::Dalli::Client::CACHE_NILS) if @cache_nils
        get(key, options).then do |response|
          not_found = @options[:cache_nils] ?
            !response.exist? :
            response.value.nil?
          if not_found && !block.nil?
            Promise.resolve(block.call).then do |new_val|
              # delay the final resolution here until after the add succeeds,
              # to guarantee errors are caught. we could potentially allow
              # the add to resolve once it's sent (without confirmation), but
              # we do need to wait on the add promise to ensure it's sent.
              add(key, new_val, ttl, options).then { new_val }
            end
          else
            Promise.resolve(response.value)
          end
        end
      end

      # Unconditionally sets the +key+ to the +value+ specified.
      # Returns a promise that resolves to a IOPromise::Dalli::Response.
      def set(key, value, ttl = nil, options = nil)
        execute_as_promise(:set, key, value, ttl_or_default(ttl), 0, options)
      end

      # Conditionally sets the +key+ to the +value+ specified.
      # Returns a promise that resolves to a IOPromise::Dalli::Response.
      def add(key, value, ttl = nil, options = nil)
        execute_as_promise(:add, key, value, ttl_or_default(ttl), options)
      end

      # Conditionally sets the +key+ to the +value+ specified only
      # if the key already exists.
      # Returns a promise that resolves to a IOPromise::Dalli::Response.
      def replace(key, value, ttl = nil, options = nil)
        execute_as_promise(:replace, key, value, ttl_or_default(ttl), 0, options)
      end

      # Deletes the specified key, resolving the promise when complete.
      def delete(key)
        execute_as_promise(:delete, key, 0)
      end

      # Appends a value to the specified key, resolving the promise when complete.
      # Appending only works for values stored with :raw => true.
      def append(key, value)
        Promise.resolve(value).then do |resolved_value|
          execute_as_promise(:append, key, resolved_value.to_s)
        end
      end
  
      # Prepend a value to the specified key, resolving the promise when complete.
      # Prepending only works for values stored with :raw => true.
      def prepend(key, value)
        Promise.resolve(value).then do |resolved_value|
          execute_as_promise(:prepend, key, resolved_value.to_s)
        end
      end

      ##
      # Incr adds the given amount to the counter on the memcached server.
      # Amt must be a positive integer value.
      #
      # If default is nil, the counter must already exist or the operation
      # will fail and will return nil.  Otherwise this method will return
      # the new value for the counter.
      #
      # Note that the ttl will only apply if the counter does not already
      # exist.  To increase an existing counter and update its TTL, use
      # #cas.
      def incr(key, amt = 1, ttl = nil, default = nil)
        raise ArgumentError, "Positive values only: #{amt}" if amt < 0
        execute_as_promise(:incr, key, amt.to_i, ttl_or_default(ttl), default)
      end

      ##
      # Decr subtracts the given amount from the counter on the memcached server.
      # Amt must be a positive integer value.
      #
      # memcached counters are unsigned and cannot hold negative values.  Calling
      # decr on a counter which is 0 will just return 0.
      #
      # If default is nil, the counter must already exist or the operation
      # will fail and will return nil.  Otherwise this method will return
      # the new value for the counter.
      #
      # Note that the ttl will only apply if the counter does not already
      # exist.  To decrease an existing counter and update its TTL, use
      # #cas.
      def decr(key, amt = 1, ttl = nil, default = nil)
        raise ArgumentError, "Positive values only: #{amt}" if amt < 0
        execute_as_promise(:decr, key, amt.to_i, ttl_or_default(ttl), default)
      end

      # TODO: touch, gat, CAS operations

      private

      def execute_as_promise(*args)
        @client.perform_async(*args)
      end

      def ttl_or_default(ttl)
        (ttl || @options[:expires_in]).to_i
      rescue NoMethodError
        raise ArgumentError, "Cannot convert ttl (#{ttl}) to an integer"
      end
    end
  end
end

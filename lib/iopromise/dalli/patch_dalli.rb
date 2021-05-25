# frozen_string_literal: true

require 'dalli'
require_relative 'response'

module IOPromise
  module Dalli
    module AsyncClient
      def initialize(servers = nil, options = {})
        @async = options[:iopromise_async] == true

        super
      end

      def perform_async(*args)
        if @async
          perform(*args)
        else
          raise ArgumentError, "Cannot perform_async when async is not enabled."
        end
      rescue => ex
        # Wrap any connection errors into a promise, this is more forwards-compatible
        # if we ever attempt to make connecting/server fallback nonblocking too.
        Promise.new.tap { |p| p.reject(ex) }
      end
    end

    module AsyncServer
      def initialize(attribs, options = {})
        @async = options.delete(:iopromise_async) == true

        if @async
          async_reset

          @next_opaque_id = 0
          @pending_ops = {}
        end

        super
      end

      def async?
        @async
      end

      def close
        if async?
          async_reset
        end

        super
      end

      def async_reset
        @write_buffer = +""
        @write_offset = 0

        @read_buffer = +""
        @read_offset = 0
      end

      # called by ExecutorPool to continue processing for this server
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        unless ready_writers.nil? || ready_writers.empty?
          # we are able to write, so write as much as we can.
          sock_write_nonblock
        end

        readers_empty = ready_readers.nil? || ready_readers.empty?
        exceptions_empty = ready_exceptions.nil? || ready_exceptions.empty?

        if !readers_empty || !exceptions_empty
          sock_read_nonblock
        end

        readers = []
        writers = []
        exceptions = [@sock]
        timeout = nil

        unless @pending_ops.empty?
          # wait for writability if we have pending data to write
          writers << @sock if @write_buffer.bytesize > @write_offset
          # and always call back when there is data available to read
          readers << @sock
        end

        [readers, writers, exceptions, timeout]
      end

      private

      REQUEST = ::Dalli::Server::REQUEST
      OPCODES = ::Dalli::Server::OPCODES
      FORMAT  = ::Dalli::Server::FORMAT


      def promised_request(key, &block)
        promise, opaque = new_pending(key)
        buffered_write(block.call(opaque))
        promise
      end

      def get(key, options = nil)
        return super unless async?

        promised_request(key) do |opaque|
          [REQUEST, OPCODES[:get], key.bytesize, 0, 0, 0, key.bytesize, opaque, 0, key].pack(FORMAT[:get])
        end
      end

      def generic_write_op(op, key, value, ttl, cas, options)
        Promise.resolve(value).then do |value|
          (value, flags) = serialize(key, value, options)
          ttl = sanitize_ttl(ttl)
    
          guard_max_value(key, value)

          promised_request(key) do |opaque|
            [REQUEST, OPCODES[op], key.bytesize, 8, 0, 0, value.bytesize + key.bytesize + 8, opaque, cas, flags, ttl, key, value].pack(FORMAT[op])
          end
        end
      end

      def set(key, value, ttl, cas, options)
        return super unless async?

        generic_write_op(:set, key, value, ttl, cas, options)
      end

      def add(key, value, ttl, options)
        return super unless async?

        generic_write_op(:add, key, value, ttl, 0, options)
      end

      def replace(key, value, ttl, cas, options)
        return super unless async?

        generic_write_op(:replace, key, value, ttl, cas, options)
      end

      def delete(key, cas)
        return super unless async?

        promised_request(key) do |opaque|
          [REQUEST, OPCODES[:delete], key.bytesize, 0, 0, 0, key.bytesize, opaque, cas, key].pack(FORMAT[:delete])
        end
      end

      def append_prepend_op(op, key, value)
        promised_request(key) do |opaque|
          [REQUEST, OPCODES[op], key.bytesize, 0, 0, 0, value.bytesize + key.bytesize, opaque, 0, key, value].pack(FORMAT[op])
        end
      end

      def append(key, value)
        return super unless async?

        append_prepend_op(:append, key, value)
      end

      def prepend(key, value)
        return super unless async?

        append_prepend_op(:prepend, key, value)
      end

      def flush
        return super unless async?

        promised_request(nil) do |opaque|
          [REQUEST, OPCODES[:flush], 0, 4, 0, 0, 4, opaque, 0, 0].pack(FORMAT[:flush])
        end
      end

      def decr_incr(opcode, key, count, ttl, default)
        expiry = default ? sanitize_ttl(ttl) : 0xFFFFFFFF
        default ||= 0
        (h, l) = split(count)
        (dh, dl) = split(default)
        promised_request(key) do |opaque|
          req = [REQUEST, OPCODES[opcode], key.bytesize, 20, 0, 0, key.bytesize + 20, opaque, 0, h, l, dh, dl, expiry, key].pack(FORMAT[opcode])
        end
      end
  
      def decr(key, count, ttl, default)
        return super unless async?

        decr_incr :decr, key, count, ttl, default
      end
  
      def incr(key, count, ttl, default)
        return super unless async?
        
        decr_incr :incr, key, count, ttl, default
      end

      def new_pending(key)
        promise = ::IOPromise::Dalli::DalliPromise.new(self, key)
        new_id = @next_opaque_id
        @pending_ops[new_id] = promise
        @next_opaque_id = (@next_opaque_id + 1) & 0xffff_ffff
        [promise, new_id]
      end

      def buffered_write(data)
        @write_buffer << data
        sock_write_nonblock
      end

      def sock_write_nonblock
        begin
          bytes_written = @sock.write_nonblock(@write_buffer.byteslice(@write_offset..-1))
        rescue IO::WaitWritable, Errno::EINTR
          return # no room to write immediately
        end
        
        @write_offset += bytes_written
        if @write_offset == @write_buffer.length
          @write_buffer = +""
          @write_offset = 0
        end
      rescue SystemCallError, Timeout::Error => e
        failure!(e)
      end

      FULL_HEADER = 'CCnCCnNNQ'

      def sock_read_nonblock
        @read_buffer << @sock.read_available

        buf = @read_buffer
        pos = @read_offset

        while buf.bytesize - pos >= 24
          header = buf.slice(pos, 24)
          (magic, opcode, key_length, extra_length, data_type, status, body_length, opaque, cas) = header.unpack(FULL_HEADER)

          if buf.bytesize - pos >= 24 + body_length
            flags = 0
            if extra_length >= 4
              flags = buf.slice(pos + 24, 4).unpack1("N")
            end

            key = buf.slice(pos + 24 + extra_length, key_length)
            value = buf.slice(pos + 24 + extra_length + key_length, body_length - key_length - extra_length)

            pos = pos + 24 + body_length

            promise = @pending_ops.delete(opaque)
            next if promise.nil?

            result = Promise.resolve(true).then do # auto capture exceptions below
              raise Dalli::DalliError, "Response error #{status}: #{Dalli::RESPONSE_CODES[status]}" unless [0,1,2,5].include?(status)

              exists = (status != 1) # Key not found
              final_value = nil
              if opcode == OPCODES[:incr] || opcode == OPCODES[:decr]
                final_value = value.unpack1("Q>")
              elsif exists
                final_value = deserialize(value, flags)
              end

              ::IOPromise::Dalli::Response.new(
                key: promise.key,
                value: final_value,
                exists: exists,
                stored: !(status == 2 || status == 5), # Key exists or Item not stored
                cas: cas,
              )
            end

            promise.fulfill(result)
            promise.execute_pool.complete(promise)
          else
            # not enough data yet, wait for more
            break
          end
        end

        @read_offset = pos

        if @read_offset == @read_buffer.length
          @read_buffer = +""
          @read_offset = 0
        end

      rescue SystemCallError, Timeout::Error, EOFError => e
        failure!(e)
      end

      def failure!(ex)
        if async?
          # all pending operations need to be rejected when a failure occurs
          @pending_ops.each do |op|
            op.reject(ex)
            op.execute_pool.complete(op)
          end
          @pending_ops = {}
        end

        super
      end

      # FIXME: this is from the master version, rather than using the yield block.
      def guard_max_value(key, value)
        return if value.bytesize <= @options[:value_max_bytes]
  
        message = "Value for #{key} over max size: #{@options[:value_max_bytes]} <= #{value.bytesize}"
        raise Dalli::ValueOverMaxSize, message
      end
    end
  end
end

::Dalli::Server.prepend(IOPromise::Dalli::AsyncServer)
::Dalli::Client.prepend(IOPromise::Dalli::AsyncClient)

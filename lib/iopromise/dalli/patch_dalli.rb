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

      def perform(*)
        return super unless @async

        begin
          super
        rescue => ex
          # Wrap any connection errors into a promise, this is more forwards-compatible
          # if we ever attempt to make connecting/server fallback nonblocking too.
          Promise.new.tap { |p| p.reject(ex) }
        end
      end
    end

    module AsyncServer
      def initialize(attribs, options = {})
        @async = options.delete(:iopromise_async) == true

        if @async
          @write_buffer = +""
          @read_buffer = +""
          async_reset

          @next_opaque_id = 0
          @pending_ops = {}

          @executor_pool = DalliExecutorPool.for(self)
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

      def connect
        super

        if async?
          @executor_pool.connected_socket(@sock)
        end
      end

      def async_reset
        @write_buffer.clear
        @write_offset = 0

        @read_buffer.clear
        @read_offset = 0

        @executor_pool.close_socket if defined? @executor_pool
      end

      def async_io_ready(readable, writable)
        async_sock_write_nonblock if writable
        async_sock_read_nonblock if readable
      end

      # called by ExecutorPool to continue processing for this server
      def execute_continue
        timeout = @options[:socket_timeout]
        @pending_ops.select! do |key, op|
          if op.timeout?
            op.reject(Timeout::Error.new)
            next false # this op is done
          end

          # let all pending operations know that they are seeing the
          # select loop. this starts the timer for the operation, because
          # it guarantees we're now working on it.
          # this is more accurate than starting the timer when we buffer
          # the write.
          op.in_select_loop

          remaining = op.timeout_remaining
          timeout = remaining if remaining < timeout

          true # keep
        end

        @executor_pool.select_timeout = timeout
        @executor_pool.set_interest(:r, !@pending_ops.empty?)
      end

      private

      REQUEST = ::Dalli::Server::REQUEST
      OPCODES = ::Dalli::Server::OPCODES
      FORMAT  = ::Dalli::Server::FORMAT


      def promised_request(key, &block)
        promise = ::IOPromise::Dalli::DalliPromise.new(self, key)
        
        new_id = @next_opaque_id
        @pending_ops[new_id] = promise
        @next_opaque_id = (@next_opaque_id + 1) & 0xffff_ffff
        
        async_buffered_write(block.call(new_id))

        promise
      end

      def get(key, options = nil)
        return super unless async?

        promised_request(key) do |opaque|
          [REQUEST, OPCODES[:get], key.bytesize, 0, 0, 0, key.bytesize, opaque, 0, key].pack(FORMAT[:get])
        end
      end

      def async_generic_write_op(op, key, value, ttl, cas, options)
        value.then do |value|
          (value, flags) = serialize(key, value, options)
          ttl = sanitize_ttl(ttl)
    
          guard_max_value_with_raise(key, value)

          promised_request(key) do |opaque|
            [REQUEST, OPCODES[op], key.bytesize, 8, 0, 0, value.bytesize + key.bytesize + 8, opaque, cas, flags, ttl, key, value].pack(FORMAT[op])
          end
        end
      end

      def set(key, value, ttl, cas, options)
        return super unless async?
        async_generic_write_op(:set, key, value, ttl, cas, options)
      end

      def add(key, value, ttl, options)
        return super unless async?

        async_generic_write_op(:add, key, value, ttl, 0, options)
      end

      def replace(key, value, ttl, cas, options)
        return super unless async?

        async_generic_write_op(:replace, key, value, ttl, cas, options)
      end

      def delete(key, cas)
        return super unless async?

        promised_request(key) do |opaque|
          [REQUEST, OPCODES[:delete], key.bytesize, 0, 0, 0, key.bytesize, opaque, cas, key].pack(FORMAT[:delete])
        end
      end

      def async_append_prepend_op(op, key, value)
        promised_request(key) do |opaque|
          [REQUEST, OPCODES[op], key.bytesize, 0, 0, 0, value.bytesize + key.bytesize, opaque, 0, key, value].pack(FORMAT[op])
        end
      end

      def append(key, value)
        return super unless async?

        async_append_prepend_op(:append, key, value)
      end

      def prepend(key, value)
        return super unless async?

        async_append_prepend_op(:prepend, key, value)
      end

      def flush
        return super unless async?

        promised_request(nil) do |opaque|
          [REQUEST, OPCODES[:flush], 0, 4, 0, 0, 4, opaque, 0, 0].pack(FORMAT[:flush])
        end
      end

      def async_decr_incr(opcode, key, count, ttl, default)
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

        async_decr_incr :decr, key, count, ttl, default
      end
  
      def incr(key, count, ttl, default)
        return super unless async?
        
        async_decr_incr :incr, key, count, ttl, default
      end

      def async_buffered_write(data)
        @write_buffer << data
        async_sock_write_nonblock
      end

      def async_sock_write_nonblock
        remaining = @write_buffer.byteslice(@write_offset, @write_buffer.length)
        begin
          bytes_written = @sock.write_nonblock(remaining, exception: false)
        rescue Errno::EINTR
          retry
        end

        return if bytes_written == :wait_writable
        
        @write_offset += bytes_written
        completed = (@write_offset == @write_buffer.length)
        if completed
          @write_buffer.clear
          @write_offset = 0
        end
        @executor_pool.set_interest(:w, !completed)
      rescue SystemCallError, Timeout::Error => e
        failure!(e)
      end

      FULL_HEADER = 'CCnCCnNNQ'

      def read_available
        loop do
          result = @sock.read_nonblock(8196, exception: false)
          if result == :wait_readable
            break
          elsif result == :wait_writable
            break
          elsif result
            @read_buffer << result
          else
            raise Errno::ECONNRESET, "Connection reset: #{safe_options.inspect}"
          end
        end
      end

      def async_sock_read_nonblock
        read_available

        buf = @read_buffer
        pos = @read_offset

        while buf.bytesize - pos >= 24
          header = buf.byteslice(pos, 24)
          (magic, opcode, key_length, extra_length, data_type, status, body_length, opaque, cas) = header.unpack(FULL_HEADER)

          if buf.bytesize - pos >= 24 + body_length
            exists = (status != 1) # Key not found
            this_pos = pos

            # key = buf.byteslice(this_pos + 24 + extra_length, key_length)
            value = buf.byteslice(this_pos + 24 + extra_length + key_length, body_length - key_length - extra_length) if exists

            pos = pos + 24 + body_length

            promise = @pending_ops.delete(opaque)
            next if promise.nil?

            begin
              raise Dalli::DalliError, "Response error #{status}: #{Dalli::RESPONSE_CODES[status]}" unless status == 0 || status == 1 || status == 2 || status == 5
              
              final_value = nil
              if opcode == OPCODES[:incr] || opcode == OPCODES[:decr]
                final_value = value.unpack1("Q>")
              elsif exists
                flags = if extra_length >= 4
                  buf.byteslice(this_pos + 24, 4).unpack1("N")
                else
                  0
                end
                final_value = deserialize(value, flags)
              end

              response = ::IOPromise::Dalli::Response.new(
                key: promise.key,
                value: final_value,
                exists: exists,
                stored: !(status == 2 || status == 5), # Key exists or Item not stored
                cas: cas,
              )

              promise.fulfill(response)
            rescue => ex
              promise.reject(ex)
            end
          else
            # not enough data yet, wait for more
            break
          end
        end

        if pos == @read_buffer.length
          @read_buffer.clear
          @read_offset = 0
        else
          @read_offset = pos
        end

      rescue SystemCallError, Timeout::Error, EOFError => e
        failure!(e)
      end

      def failure!(ex)
        if async?
          # all pending operations need to be rejected when a failure occurs
          @pending_ops.each do |op|
            op.reject(ex)
          end
          @pending_ops = {}
        end

        super
      end

      # this is guard_max_value from the master version, rather than using the yield block.
      def guard_max_value_with_raise(key, value)
        return if value.bytesize <= @options[:value_max_bytes]
  
        message = "Value for #{key} over max size: #{@options[:value_max_bytes]} <= #{value.bytesize}"
        raise Dalli::ValueOverMaxSize, message
      end
    end
  end
end

::Dalli::Server.prepend(IOPromise::Dalli::AsyncServer)
::Dalli::Client.prepend(IOPromise::Dalli::AsyncClient)

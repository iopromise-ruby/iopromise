# frozen_string_literal: true

require 'ethon'

Ethon::Curl.ffi_lib 'curl'
Ethon::Curl.attach_function :multi_socket_action, :curl_multi_socket_action, [:pointer, :int, :int, :pointer], :multi_code

module IOPromise
  module Faraday
    class MultiSocketAction < Ethon::Multi
      CURL_POLL_NONE = 0
      CURL_POLL_IN = 1
      CURL_POLL_OUT = 2
      CURL_POLL_INOUT = 3
      CURL_POLL_REMOVE = 4
    
      CURL_SOCKET_BAD = -1
      CURL_SOCKET_TIMEOUT = CURL_SOCKET_BAD
    
      CURLM_OK = 0

      CURL_CSELECT_IN  = 0x01
      CURL_CSELECT_OUT = 0x02
      CURL_CSELECT_ERR = 0x04

      attr_accessor :iop_handler
      
      def initialize(options = {})
        super(options)
    
        @ios = {}
        @iop_handler = nil
        @notified_fds = 0
    
        self.socketfunction = @keep_socketfunction = proc do |handle, sock, what, userp, socketp|
          if what == CURL_POLL_REMOVE
            io = @ios.delete(sock)
            iop_handler.monitor_remove(io) unless io.nil?
          else
            # reuse existing if we have it anywhere
            io = @ios[sock]
            if io.nil?
              io = @ios[sock] = IO.for_fd(sock).tap { |io| io.autoclose = false }
              iop_handler.monitor_add(io)
            end
            if what == CURL_POLL_INOUT
              iop_handler.set_interests(io, :rw)
            elsif what == CURL_POLL_IN
              iop_handler.set_interests(io, :r)
            elsif what == CURL_POLL_OUT
              iop_handler.set_interests(io, :w)
            end
          end
          CURLM_OK
        end
    
        self.timerfunction = @keep_timerfunction = proc do |handle, timeout_ms, userp|
          if timeout_ms > 0x7fffffffffffffff # FIXME: wrongly encoded
            select_timeout = nil
          else
            select_timeout = timeout_ms.to_f / 1_000
          end
          iop_handler.set_timeout(select_timeout)
          CURLM_OK
        end
      end
    
      def perform
        # stubbed out, we don't want any of the multi_perform logic
      end
    
      def run
        # stubbed out, we don't want any of the multi_perform logic
      end

      def socket_is_ready(io, readable, writable)
        running_handles = ::FFI::MemoryPointer.new(:int)

        bitmask = 0
        bitmask |= CURL_CSELECT_IN if readable
        bitmask |= CURL_CSELECT_OUT if writable

        Ethon::Curl.multi_socket_action(handle, io.fileno, bitmask, running_handles)
        @notified_fds += 1
      end
    
      def execute_continue
        running_handles = ::FFI::MemoryPointer.new(:int)
    
        if @notified_fds == 0
          # no FDs were readable/writable so we send the timeout fd, which lets
          # curl perform housekeeping.
          Ethon::Curl.multi_socket_action(handle, CURL_SOCKET_TIMEOUT, 0, running_handles)
        else
          @notified_fds = 0
        end
    
        check
      end
    end
  end
end

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
      
      def initialize(options = {})
        super(options)
    
        @read_fds = {}
        @write_fds = {}
        @select_timeout = nil
    
        self.socketfunction = @keep_socketfunction = proc do |handle, sock, what, userp, socketp|
          if what == CURL_POLL_REMOVE
            @read_fds.delete(sock)
            @write_fds.delete(sock)
          else
            # reuse existing if we have it anywhere
            io = @read_fds[sock] || @write_fds[sock] || IO.for_fd(sock).tap { |io| io.autoclose = false }
            if what == CURL_POLL_INOUT
              @read_fds[sock] = io
              @write_fds[sock] = io
            elsif what == CURL_POLL_IN
              @read_fds[sock] = io
              @write_fds.delete(sock)
            elsif what == CURL_POLL_OUT
              @read_fds.delete(sock)
              @write_fds[sock] = io
            end
          end
          CURLM_OK
        end
    
        self.timerfunction = @keep_timerfunction = proc do |handle, timeout_ms, userp|
          if timeout_ms > 0x7fffffffffffffff # FIXME: wrongly encoded
            @select_timeout = nil
          else
            @select_timeout = timeout_ms.to_f / 1_000
          end
          CURLM_OK
        end
      end
    
      def perform
        # stubbed out, we don't want any of the multi_perform logic
      end
    
      def run
        # stubbed out, we don't want any of the multi_perform logic
      end
    
      def execute_continue(ready_readers, ready_writers, ready_exceptions)
        running_handles = ::FFI::MemoryPointer.new(:int)
        
        flags = Hash.new(0)
    
        unless ready_readers.nil?
          ready_readers.each do |s|
            flags[s.fileno] |= CURL_CSELECT_IN
          end
        end
        unless ready_writers.nil?
          ready_writers.each do |s|
            flags[s.fileno] |= CURL_CSELECT_OUT
          end
        end
        unless ready_exceptions.nil?
          ready_exceptions.each do |s|
            flags[s.fileno] |= CURL_CSELECT_ERR
          end
        end
        
        flags.each do |fd, bitmask|
          Ethon::Curl.multi_socket_action(handle, fd, bitmask, running_handles)
        end
    
        if flags.empty?
          Ethon::Curl.multi_socket_action(handle, CURL_SOCKET_TIMEOUT, 0, running_handles)
        end
    
        check
    
        [@read_fds.values, @write_fds.values, [], @select_timeout]
      end
    end
  end
end

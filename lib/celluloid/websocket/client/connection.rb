require 'forwardable'

module Celluloid
  module WebSocket
    module Client
      class Connection
        include Celluloid::IO
        extend Forwardable

        attr_reader :url, :connected

        def_delegators :@client, :text, :binary, :ping, :close, :protocol

        def initialize(url, handler)
          @url = url
          @connected = false
          start(handler)
        end

        def start(handler)
          return unless handler.alive?
          uri = URI.parse(url)
          port = uri.port || (uri.scheme == "ws" ? 80 : 443)
          begin
            @socket = Celluloid::IO::TCPSocket.new(uri.host, port)
            if uri.scheme == "wss"
              @socket = Celluloid::IO::SSLSocket.new(@socket)
              @socket.connect
            end
          rescue => e
            handler.async.on_error(::WebSocket::Driver::Hybi::ERRORS[:protocol_error], e.to_s)
            terminate
          end
          @client = ::WebSocket::Driver.client(self)
          @handler = handler

          async.run
        end

        def connected?
          connected
        end

        def disconnected?
          !connected
        end

        def run
          @client.on('open') do |_event|
            if @handler.respond_to?(:on_open)
              @connected = true
              @handler.async.on_open
            end
          end

          @client.on('message') do |event|
            if @handler.respond_to?(:on_message)
              @connected = true if disconnected?
              @handler.async.on_message(event.data)
            end
          end

          @client.on('close') do |event|
            if @handler.respond_to?(:on_close)
              @connected = false
              @handler.async.on_close(event.code, event.reason)
            end
          end

          @client.on('error') do |event|
            if @handler.respond_to?(:on_error)
              @connected = false
              @handler.async.on_error(event.code, event.reason)
            end
          end

          @client.start

          loop do
            begin
              @client.parse(@socket.readpartial(1024))
            rescue EOFError
              break
            end
          end
          @connected = false
        end

        def write(buffer)
          @socket.write(buffer)
        end
      end
    end
  end
end

require 'forwardable'

module Celluloid
  module WebSocket
    module Client
      class Connection
        include Celluloid::IO
        include Celluloid::Logger
        extend Forwardable

        PART_SIZE = 1024

        def_delegator :@client, :start, :start
        def_delegators :@client, :text, :binary, :ping, :close, :protocol

        attr_reader :url

        def initialize(url, handler)
          @url = url
          @handler = handler
        end

        def start
          debug("Celluloid::WebSocket::Client::Connection start")
          uri = URI.parse(url)
          port = uri.port || (uri.scheme == "ws" ? 80 : 443)

          begin
            @socket = Celluloid::IO::TCPSocket.new(uri.host, port)
            if uri.scheme == "wss"
              @socket = Celluloid::IO::SSLSocket.new(@socket)
              @socket.connect
            end
          rescue => e
            @handler.async.on_error(::WebSocket::Driver::Hybi::ERRORS[:protocol_error], e.to_s)
          end

          @client = ::WebSocket::Driver.client(self)

          async.run
        end

        def run
          @client.on('open') do |_event|
            @handler.async.on_open if @handler.respond_to?(:on_open)
          end

          @client.on('message') do |event|
            @handler.async.on_message(event.data) if @handler.respond_to?(:on_message)
          end

          @client.on('close') do |event|
            @handler.async.on_close(event.code, event.reason) if @handler.respond_to?(:on_close)
          end

          @client.on('error') do |event|
            @handler.async.on_error(event.code, event.reason) if @handler.respond_to?(:on_error)
          end

          @client.start

          loop do
            begin
              @client.parse(@socket.readpartial(PART_SIZE))
            rescue EOFError
              break
            end
          end
        end

        def write(buffer)
          @socket.write(buffer)
        end
      end
    end
  end
end

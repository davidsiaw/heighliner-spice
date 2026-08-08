# frozen_string_literal: true

require 'socket'

module Spice
  # Accepts stream connections and gives each one a thread. One connection runs
  # exactly one command, so there is nothing to multiplex.
  class Listener
    def initialize(port: Config.stream_port, host: '0.0.0.0')
      @port = port
      @host = host
    end

    def start
      server = TCPServer.new(@host, @port)
      loop do
        sock = server.accept
        Thread.new(sock) do |s|
          s.sync = true
          Session.new(s).run
        end
      end
    end
  end
end

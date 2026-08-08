# frozen_string_literal: true

require 'socket'
require 'uri'

module SpiceClient
  # Where the spice server is, and how to open a connection to it.
  #
  # Both failures here are the user's to fix and neither is fixable from inside
  # the sandbox, so the messages say so plainly rather than reporting an
  # exception and leaving the reader to guess.
  class Endpoint
    DEFAULT_STREAM_PORT = 7530

    attr_reader :host, :port

    def initialize(url: ENV['SPICE_URL'].to_s, port: ENV['SPICE_STREAM_PORT'])
      raise Failure, <<~MSG if url.empty?
        heighliner: SPICE_URL is not set, so there is no docker to talk to.

        This sandbox has no docker socket. Start a spice server on the host
        (`sp up`) and relaunch the sandbox so it gets SPICE_URL.
      MSG

      # SPICE_URL names the health endpoint; only its host is used here.
      @host = URI.parse(url).host || url
      @port = Integer(port || DEFAULT_STREAM_PORT)
    end

    def connect
      TCPSocket.new(@host, @port).tap { |sock| sock.sync = true }
    rescue SocketError, SystemCallError => e
      # SocketError covers DNS failure, which is what you get when the spice
      # container is not running, or this container is not on its network.
      raise Failure, <<~MSG
        heighliner: cannot reach the spice server at #{@host}:#{@port}
          #{e.class}: #{e.message}

        Is it up? On the host: `sp status`, and `sp up` if not.
      MSG
    end
  end
end

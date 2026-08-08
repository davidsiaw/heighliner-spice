# frozen_string_literal: true

require 'socket'
require 'uri'

module SpiceClient
  # Where the spice server is, and how to open a connection to it.
  class Endpoint
    DEFAULT_STREAM_PORT = 7530

    attr_reader :host, :port

    def self.from_env
      new(url: env_var('SPICE_URL'), port: env_var('SPICE_STREAM_PORT'))
    end

    # An empty variable means unset; docker supplies one for every `-e NAME=`.
    def self.stream_port(raw)
      raw = raw.to_s
      raw.empty? ? DEFAULT_STREAM_PORT : Integer(raw)
    end

    def self.env_var(name)
      ENV.fetch(name, nil)
    end
    private_class_method :env_var

    def initialize(url:, port: nil)
      url = url.to_s

      raise Failure, <<~MSG if url.empty?
        heighliner: SPICE_URL is not set, so there is no docker to talk to.

        This sandbox has no docker socket. Start a spice server on the host
        (`sp up`) and relaunch the sandbox so it gets SPICE_URL.
      MSG

      # SPICE_URL names the health endpoint; only its host is used here.
      @host = URI.parse(url).host || url
      @port = self.class.stream_port(port)
    end

    def connect
      TCPSocket.new(@host, @port).tap { |sock| sock.sync = true }
    rescue SocketError, SystemCallError => e
      # SocketError here means DNS failed, i.e. no spice container.
      raise Failure, <<~MSG
        heighliner: cannot reach the spice server at #{@host}:#{@port}
          #{e.class}: #{e.message}

        Is it up? On the host: `sp status`, and `sp up` if not.
      MSG
    end
  end
end

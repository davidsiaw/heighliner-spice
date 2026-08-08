# frozen_string_literal: true

# Spice server.
#
# Runs inside a container that has /var/run/docker.sock and the host project
# tree mounted at its real path. Accepts heighliner argv from sandboxed agents
# that have no docker of their own, runs the real heighliner attached to a pty,
# and proxies that pty back over a socket.
#
# Two listeners:
#   SPICE_PORT         HTTP, /health only
#   SPICE_STREAM_PORT  the framed duplex protocol that actually runs commands
#
# The duplex socket is what makes `attach`, `login` and `root` work: they need
# stdin and window-size changes travelling the other way, which a single HTTP
# request/response cannot express.
#
# This process holds the docker socket on behalf of whoever can reach it. It
# requires a shared token. Do not expose it beyond a local docker network.
#
# The pieces:
#   server/config.rb    environment settings
#   server/errors.rb    Denied, the one error a client is told about
#   server/frame.rb     the wire format, shared with the client
#   server/request.rb   the opening header: auth, argv, cwd, env, terminal
#   server/command.rb   one heighliner run on a pty
#   server/session.rb   one connection: socket <-> pty
#   server/health.rb    the HTTP health endpoint
#   server/listener.rb  accept loop

# Load order does not matter: every reference between these files happens at
# call time, not load time. Reintroducing a load-time dependency (a superclass,
# or a constant assigned from another file) would make this alphabetical order
# load-bearing, so do not.
Dir.glob("#{__dir__}/server/*.rb").sort.each { |piece| require piece }

module Spice
  module_function

  def run
    warn 'spice: SPICE_TOKEN is empty, running unauthenticated' unless Config.authenticated?

    health = Health.server
    Thread.new { health.start }

    %w[INT TERM].each do |signal|
      trap(signal) do
        health.shutdown
        exit 0
      end
    end

    warn "spice: health on 0.0.0.0:#{Config.health_port}, " \
         "stream on 0.0.0.0:#{Config.stream_port}"

    Listener.new.start
  end
end

Spice.run if $PROGRAM_NAME == __FILE__

# frozen_string_literal: true

require 'webrick'
require 'json'

module Spice
  # A plain HTTP endpoint so `sp status` can ask whether the server is alive
  # without speaking the stream protocol.
  module Health
    class Servlet < WEBrick::HTTPServlet::AbstractServlet
      def do_GET(_req, res) # rubocop:disable Naming/MethodName
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate(
          ok: true,
          auth: Config.authenticated?,
          stream_port: Config.stream_port
        )
      end
    end

    module_function

    def server
      server = WEBrick::HTTPServer.new(
        Port: Config.health_port,
        BindAddress: '0.0.0.0',
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
        AccessLog: []
      )
      server.mount '/health', Servlet
      server
    end
  end
end

# frozen_string_literal: true

require 'webrick'
require 'json'

module Spice
  # Lets `sp status` ask whether the server is alive without speaking the
  # stream protocol.
  module Health
    def self.server
      server = WEBrick::HTTPServer.new(
        Port: Config.health_port,
        BindAddress: '0.0.0.0',
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
        AccessLog: []
      )
      server.mount_proc('/health') { |_req, res| respond(res) }
      server
    end

    def self.respond(res)
      res.status = 200
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(ok: true, auth: Config.authenticated?, stream_port: Config.stream_port)
    end
  end
end

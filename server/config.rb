# frozen_string_literal: true

module Spice
  # Everything the server reads from its environment.
  module Config
    # Anything not listed is dropped: a sandbox must not be able to set PATH or
    # LD_PRELOAD on a process holding the docker socket.
    ENV_ALLOWLIST = %w[OP_SERVICE_ACCOUNT_TOKEN].freeze

    # An empty variable means unset. Docker hands one over for every `-e NAME=`,
    # and dying at boot over it would be a poor trade.
    def self.port(name, default)
      raw = env_var(name).to_s
      raw.empty? ? default : Integer(raw)
    end

    def self.health_port
      port('SPICE_PORT', 7529)
    end

    def self.stream_port
      port('SPICE_STREAM_PORT', 7530)
    end

    def self.token
      env_var('SPICE_TOKEN').to_s
    end

    def self.authenticated?
      !token.empty?
    end

    def self.env_var(name)
      ENV.fetch(name, nil)
    end
    private_class_method :env_var
  end
end

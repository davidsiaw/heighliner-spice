# frozen_string_literal: true

module Spice
  # Everything the server reads from its environment, in one place.
  module Config
    module_function

    def health_port
      Integer(ENV['SPICE_PORT'] || 7529)
    end

    def stream_port
      Integer(ENV['SPICE_STREAM_PORT'] || 7530)
    end

    def token
      ENV['SPICE_TOKEN'].to_s
    end

    def authenticated?
      !token.empty?
    end

    # Env vars a client is allowed to set on the server-side run. Everything
    # else is dropped, so a sandbox cannot inject PATH or LD_PRELOAD into a
    # process that holds the docker socket.
    ENV_ALLOWLIST = %w[OP_SERVICE_ACCOUNT_TOKEN].freeze
  end
end

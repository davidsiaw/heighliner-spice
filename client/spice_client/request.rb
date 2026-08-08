# frozen_string_literal: true

require 'json'

module SpiceClient
  # The opening header. Parsed by spice/server/request.rb.
  class Request
    # The server ignores anything else, so there is no point sending more.
    FORWARDED_ENV = %w[OP_SERVICE_ACCOUNT_TOKEN].freeze

    def initialize(argv:, terminal:, token: nil)
      @argv = argv
      @terminal = terminal
      @token = (token || env_var('SPICE_TOKEN')).to_s
    end

    def to_line
      "#{JSON.generate(to_h)}\n"
    end

    def to_h
      rows, cols = @terminal.size
      {
        token: @token,
        argv: @argv,
        # The server must see this exact absolute path; see docs/architecture.md.
        cwd: Dir.pwd,
        env: forwarded_env,
        tty: @terminal.tty?,
        rows: rows,
        cols: cols
      }
    end

    def forwarded_env
      FORWARDED_ENV.each_with_object({}) do |key, out|
        value = env_var(key)
        out[key] = value if value
      end
    end

    private

    def env_var(name)
      ENV.fetch(name, nil)
    end
  end
end

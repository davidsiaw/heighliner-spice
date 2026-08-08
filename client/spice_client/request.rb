# frozen_string_literal: true

require 'json'

module SpiceClient
  # The opening header, parsed on the far end by spice/server/request.rb.
  #
  # `cwd` is the whole reason spice works: the server must see this directory at
  # this exact absolute path, so it is sent rather than assumed.
  class Request
    # Env vars worth forwarding. The server ignores anything else, so there is
    # no point sending more.
    FORWARDED_ENV = %w[OP_SERVICE_ACCOUNT_TOKEN].freeze

    def initialize(argv:, terminal:, token: ENV['SPICE_TOKEN'].to_s)
      @argv = argv
      @terminal = terminal
      @token = token
    end

    def to_line
      "#{JSON.generate(to_h)}\n"
    end

    private

    def to_h
      rows, cols = @terminal.size
      {
        token: @token,
        argv: @argv,
        cwd: Dir.pwd,
        env: forwarded_env,
        tty: @terminal.tty?,
        rows: rows,
        cols: cols
      }
    end

    def forwarded_env
      FORWARDED_ENV.each_with_object({}) do |key, out|
        value = ENV.fetch(key, nil)
        out[key] = value if value
      end
    end
  end
end

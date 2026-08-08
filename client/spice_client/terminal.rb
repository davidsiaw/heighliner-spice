# frozen_string_literal: true

require 'io/console'

module SpiceClient
  # This end's terminal, or the absence of one. Whether we are a terminal
  # decides how the server's pty behaves; see spice/docs/protocol.md#terminals.
  class Terminal
    def initialize(input: $stdin, output: $stdout, error: $stderr)
      @input = input
      @output = output
      @error = error
    end

    def tty?
      @output.tty?
    end

    def size
      return [0, 0] unless tty?

      @output.winsize
    rescue StandardError
      [0, 0]
    end

    # Raw mode is what sends ^C to the *remote* process group instead of killing
    # this client and orphaning the command.
    def raw(&)
      return yield unless @input.tty?

      @input.raw(&)
    end

    def on_resize
      trap('WINCH') do
        rows, cols = size
        yield(rows, cols) if rows.positive?
      rescue StandardError
        nil
      end
    end

    def readable
      @input
    end

    def write(bytes)
      @output.write(bytes)
      @output.flush
    end

    def warn(message)
      @error.puts(message)
    end
  end
end

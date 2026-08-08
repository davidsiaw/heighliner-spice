# frozen_string_literal: true

require 'io/console'

module SpiceClient
  # This end's terminal, or the absence of one.
  #
  # Whether we are a terminal decides how the far end behaves: the server only
  # puts its pty in terminal mode when there is a terminal here to serve.
  class Terminal
    def initialize(input: $stdin, output: $stdout)
      @input = input
      @output = output
    end

    def tty?
      @output.tty?
    end

    # [rows, cols], or [0, 0] when there is no terminal to ask.
    def size
      return [0, 0] unless tty?

      @output.winsize
    rescue StandardError
      [0, 0]
    end

    # Raw mode stops the local terminal from interpreting ^C, so the byte
    # travels to the remote pty and the *remote* process group gets the signal.
    # Without it, ^C would kill this client and orphan the command on the server.
    def raw(&block)
      return yield unless @input.tty?

      @input.raw(&block)
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
  end
end

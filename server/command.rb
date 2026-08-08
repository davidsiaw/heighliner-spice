# frozen_string_literal: true

require 'pty'
require 'io/console'

module Spice
  # One run of the real heighliner, on a pty.
  class Command
    PROGRAM = 'heighliner'

    # $0 is the program, $1 the directory, and the rest the arguments. Nothing
    # is interpolated, so nothing the client sent is ever parsed by the shell.
    SCRIPT = 'cd "$1" && shift && exec "$0" "$@"'

    attr_reader :reader, :writer, :pid

    def initialize(request, program: PROGRAM)
      @request = request
      @program = program
    end

    def start
      @reader, @writer, @pid = PTY.spawn(
        @request.env, '/bin/sh', '-c', SCRIPT,
        @program, @request.cwd, *@request.argv
      )

      # Raw for a non-terminal client, or its output arrives full of ^M.
      raw! unless @request.tty?
      resize(@request.rows, @request.cols)
      self
    end

    def write(bytes)
      @writer.write(bytes)
    rescue Errno::EIO, IOError
      nil
    end

    def end_input
      write("\x04")
    end

    def resize(rows, cols)
      rows = rows.to_i
      cols = cols.to_i
      return if rows <= 0 || cols <= 0

      @reader.winsize = [rows, cols]
    rescue StandardError
      nil
    end

    def stop
      terminate
      code = reap
      close
      code
    end

    private

    def raw!
      @reader.raw!
    rescue StandardError
      nil
    end

    def terminate
      Process.kill('TERM', @pid)
    rescue Errno::ESRCH, RangeError
      nil
    end

    def reap
      _, status = Process.waitpid2(@pid)
      status.exitstatus || (128 + status.termsig.to_i)
    rescue Errno::ECHILD
      0
    end

    def close
      [@reader, @writer].each do |io|
        io.close
      rescue StandardError
        nil
      end
    end
  end
end

# frozen_string_literal: true

require 'pty'
require 'io/console'

module Spice
  # One run of the real heighliner, on a pty.
  #
  # The pty is not optional: it is what makes `docker exec -ti` work at all, and
  # what keeps docker's build output unbuffered. Everything else here is about
  # making that pty behave for whoever is on the far end.
  class Command
    attr_reader :reader, :writer, :pid

    def initialize(request)
      @request = request
    end

    def start
      # $0 and $@ carry cwd and argv as separate words, so nothing the client
      # sent is ever parsed by the shell.
      @reader, @writer, @pid = PTY.spawn(
        @request.env, '/bin/sh', '-c', 'cd "$0" && exec heighliner "$@"',
        @request.cwd, *@request.argv
      )

      # For a client that is not a terminal -- an agent capturing output -- the
      # line discipline is pure noise: it would litter every line with ^M and
      # echo back anything piped in.
      raw! unless @request.tty?
      resize(@request.rows, @request.cols)
      self
    end

    def write(bytes)
      @writer.write(bytes)
    rescue Errno::EIO, IOError
      # Child is gone; the read side will notice and end the loop.
    end

    # Ctrl-D, so a command reading stdin sees end-of-input through the tty.
    def end_input
      write("\x04")
    end

    def resize(rows, cols)
      rows = rows.to_i
      cols = cols.to_i
      return if rows <= 0 || cols <= 0

      @reader.winsize = [rows, cols]
    rescue StandardError
      # Not fatal: the command just runs at the default size.
    end

    # Ends the command if it is still running and returns its exit code.
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

# frozen_string_literal: true

module Spice
  # One client connection: parse the header, run the command, and shuttle bytes
  # between the socket and the pty until one of them ends.
  class Session
    CHUNK = 65_536

    def initialize(sock)
      @sock = sock
      @buf = +''.b
    end

    def run
      request = Request.parse(@sock.gets("\n"))
      command = Command.new(request).start
      begin
        pump(command)
      ensure
        send_frame(Frame::EXIT, command.stop.to_s)
      end
    rescue Denied => e
      send_frame(Frame::ERROR, e.message)
    rescue StandardError => e
      send_frame(Frame::ERROR, "spice: #{e.class}: #{e.message}")
    ensure
      close
    end

    private

    def pump(command)
      loop do
        ready, = IO.select([@sock, command.reader])
        return unless ready

        return if ready.include?(command.reader) && !forward_output(command)
        return if ready.include?(@sock) && !forward_input(command)
      end
    end

    # Returns false when the command is finished.
    def forward_output(command)
      send_frame(Frame::DATA, command.reader.read_nonblock(CHUNK))
      true
    rescue IO::WaitReadable
      true # Spurious wakeup.
    rescue EOFError, Errno::EIO
      false # The child closed the pty.
    end

    # Returns false when the client is gone.
    def forward_input(command)
      @buf << @sock.read_nonblock(CHUNK)
      Frame.drain(@buf) { |type, payload| dispatch(command, type, payload) }
      true
    rescue IO::WaitReadable
      true
    rescue EOFError, Errno::ECONNRESET
      # Do not leave the command running with nobody watching it.
      false
    end

    def dispatch(command, type, payload)
      case type
      when Frame::DATA      then command.write(payload)
      when Frame::STDIN_EOF then command.end_input
      when Frame::RESIZE    then command.resize(*payload.split)
      end
    end

    def send_frame(type, payload = '')
      @sock.write(Frame.pack(type, payload))
    rescue StandardError
      # Client is gone; nothing useful left to do.
    end

    def close
      @sock.close
    rescue StandardError
      nil
    end
  end
end

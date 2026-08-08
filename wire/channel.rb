# frozen_string_literal: true

module SpiceWire
  # A socket that carries frames.
  #
  # Owns the read buffer, so partial frames, would-block reads and a vanished
  # peer are handled in one place instead of by everyone holding a socket.
  class Channel
    CHUNK = 65_536

    def initialize(socket)
      @socket = socket
      @buf = Frame.buffer
    end

    # False when the peer has gone; there is never anything useful to do about
    # a failed write except stop.
    def send_frame(type, payload = '')
      @socket.write(Frame.pack(type, payload))
      true
    rescue StandardError
      false
    end

    # The frames that have arrived, [] if none yet, or nil once the peer is gone.
    def receive_frames
      @buf << @socket.read_nonblock(CHUNK)
      frames = []
      Frame.drain(@buf) { |type, payload| frames << [type, payload] }
      frames
    rescue IO::WaitReadable
      []
    rescue IOError, Errno::ECONNRESET
      nil
    end

    # The opening header is a line of JSON rather than a frame.
    def send_frame_line(line)
      @socket.write(line)
      true
    rescue StandardError
      false
    end

    def read_line
      @socket.gets("\n")
    end

    # Lets a Channel be handed straight to IO.select.
    def to_io
      @socket
    end

    def wait_readable(timeout = nil)
      @socket.wait_readable(timeout)
    end

    def close
      @socket.close
    rescue StandardError
      nil
    end

    def closed?
      @socket.closed?
    end
  end
end

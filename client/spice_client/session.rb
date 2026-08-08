# frozen_string_literal: true

module SpiceClient
  # The connection, once it is open: shuttle bytes between this terminal and the
  # server until the server reports an exit code.
  class Session
    CHUNK = 65_536

    def initialize(socket, terminal)
      @socket = socket
      @terminal = terminal
      @buf = +''.b
      @stdin_open = true
      @exit_code = nil
    end

    # Returns the command's exit code.
    def run(request)
      @socket.write(request.to_line)
      @terminal.on_resize { |rows, cols| send(Frame::RESIZE, "#{rows} #{cols}") }
      @terminal.raw { pump }

      return @exit_code if @exit_code

      raise Failure, "\nheighliner: spice connection ended without an exit code"
    end

    private

    def pump
      loop do
        ready, = IO.select(watched)
        next unless ready

        forward_input if ready.include?(@terminal.readable)
        break if ready.include?(@socket) && !receive
      end
    end

    def watched
      @stdin_open ? [@socket, @terminal.readable] : [@socket]
    end

    def forward_input
      send(Frame::DATA, @terminal.readable.read_nonblock(CHUNK))
    rescue IO::WaitReadable
      nil
    rescue EOFError
      send(Frame::STDIN_EOF)
      @stdin_open = false
    end

    # Returns false once there is nothing more to wait for.
    def receive
      @buf << @socket.read_nonblock(CHUNK)
      keep_going = true
      Frame.drain(@buf) { |type, payload| keep_going = false unless handle(type, payload) }
      keep_going
    rescue IO::WaitReadable
      true
    rescue EOFError, Errno::ECONNRESET
      false
    end

    # Returns false when this frame ends the session.
    def handle(type, payload)
      case type
      when Frame::DATA
        @terminal.write(payload)
        true
      when Frame::EXIT
        @exit_code = payload.to_i
        false
      when Frame::ERROR
        warn "\nheighliner: #{payload}"
        @exit_code = 1
        false
      else
        true
      end
    end

    def send(type, payload = '')
      @socket.write(Frame.pack(type, payload))
    end
  end
end

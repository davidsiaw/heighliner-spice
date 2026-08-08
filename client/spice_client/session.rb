# frozen_string_literal: true

module SpiceClient
  # The connection once it is open: shuttle bytes until the server reports an
  # exit code.
  class Session
    Frame = SpiceWire::Frame

    attr_reader :exit_code

    def initialize(socket, terminal)
      @channel = SpiceWire::Channel.new(socket)
      @terminal = terminal
      @stdin_open = true
      @exit_code = nil
    end

    def run(request)
      @channel.send_frame_line(request.to_line)
      @terminal.on_resize { |rows, cols| @channel.send_frame(Frame::RESIZE, "#{rows} #{cols}") }
      @terminal.raw { pump }

      return @exit_code if @exit_code

      raise Failure, "\nheighliner: spice connection ended without an exit code"
    end

    def pump
      loop do
        ready, = IO.select(watched)
        next unless ready

        forward_input if ready.include?(@terminal.readable)
        break if ready.include?(@channel) && server_done?
      end
    end

    def watched
      @stdin_open ? [@channel, @terminal.readable] : [@channel]
    end

    def forward_input
      @channel.send_frame(Frame::DATA, @terminal.readable.read_nonblock(SpiceWire::Channel::CHUNK))
    rescue IO::WaitReadable
      nil
    rescue EOFError
      @channel.send_frame(Frame::STDIN_EOF)
      @stdin_open = false
    end

    # True once there is nothing left to wait for: either the server reported an
    # exit code, or it went away without one.
    def server_done?
      frames = @channel.receive_frames
      return true if frames.nil?

      frames.each { |type, payload| handle(type, payload) }
      finished?
    end

    def handle(type, payload)
      case type
      when Frame::DATA  then @terminal.write(payload)
      when Frame::EXIT  then @exit_code = payload.to_i
      when Frame::ERROR then fail_with(payload)
      end
    end

    def fail_with(message)
      @terminal.warn("\nheighliner: #{message}")
      @exit_code = 1
    end

    def finished?
      !@exit_code.nil?
    end
  end
end

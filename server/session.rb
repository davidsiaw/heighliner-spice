# frozen_string_literal: true

module Spice
  # One client connection: run the command, shuttle bytes until either end stops.
  class Session
    Frame = SpiceWire::Frame

    def initialize(socket, program: Command::PROGRAM)
      @channel = SpiceWire::Channel.new(socket)
      @program = program
    end

    def run
      execute(Request.parse(@channel.read_line))
    rescue Denied => e
      @channel.send_frame(Frame::ERROR, e.message)
    rescue StandardError => e
      @channel.send_frame(Frame::ERROR, "spice: #{e.class}: #{e.message}")
    ensure
      close
    end

    def execute(request)
      command = Command.new(request, program: @program).start
      pump(command)
    ensure
      @channel.send_frame(Frame::EXIT, command.stop.to_s) if command
    end

    def pump(command)
      loop do
        ready, = IO.select([@channel, command.reader])
        return unless ready
        return if ready.include?(command.reader) && command_finished?(command)
        return if ready.include?(@channel) && client_gone?(command)
      end
    end

    # Sends whatever the command has produced. True once it has closed its pty.
    def command_finished?(command)
      @channel.send_frame(Frame::DATA, command.reader.read_nonblock(SpiceWire::Channel::CHUNK))
      false
    rescue IO::WaitReadable
      false
    rescue EOFError, Errno::EIO
      true
    end

    # Dispatches whatever the client sent. True once the client has vanished,
    # which is what makes execute kill the command rather than orphan it.
    def client_gone?(command)
      frames = @channel.receive_frames
      return true if frames.nil?

      frames.each { |type, payload| dispatch(command, type, payload) }
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
      @channel.send_frame(type, payload)
    end

    def close
      @channel.close
    end
  end
end

# frozen_string_literal: true

RSpec.describe SpiceClient::Session do
  describe '#run' do
    it 'returns the exit code the server reported' do
      mine, theirs = UNIXSocket.pair
      input, = IO.pipe
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '7'))
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      request = SpiceClient::Request.new(argv: ['show'], terminal: terminal, token: '')

      expect(Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }).to eq(7)
    end

    it 'sends the header before anything else, because the server reads it with gets' do
      mine, theirs = UNIXSocket.pair
      input, = IO.pipe
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '0'))
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      request = SpiceClient::Request.new(argv: ['show'], terminal: terminal, token: '')
      Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }

      expect(JSON.parse(SpiceWire::Channel.new(theirs).read_line)['argv']).to eq(['show'])
    end

    it 'writes data frames to the terminal' do
      mine, theirs = UNIXSocket.pair
      input, = IO.pipe
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'building...'))
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '0'))
      out = StringIO.new
      terminal = SpiceClient::Terminal.new(input: input, output: out)
      request = SpiceClient::Request.new(argv: ['up'], terminal: terminal, token: '')
      Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }

      expect(out.string).to eq('building...')
    end

    it 'forwards what the user types as a data frame' do
      mine, theirs = UNIXSocket.pair
      input, input_writer = IO.pipe
      input_writer.write("typed\n")
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '0'))
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      request = SpiceClient::Request.new(argv: ['login'], terminal: terminal, token: '')
      Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }
      channel = SpiceWire::Channel.new(theirs)
      channel.read_line

      expect(channel.receive_frames).to include([SpiceWire::Frame::DATA, "typed\n"])
    end

    it 'tells the server when stdin runs out, so a command reading input can finish' do
      mine, theirs = UNIXSocket.pair
      input, input_writer = IO.pipe
      input_writer.close
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '0'))
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      request = SpiceClient::Request.new(argv: ['login'], terminal: terminal, token: '')
      Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }
      channel = SpiceWire::Channel.new(theirs)
      channel.read_line

      expect(channel.receive_frames).to include([SpiceWire::Frame::STDIN_EOF, ''])
    end

    it 'reports an error frame to the user' do
      mine, theirs = UNIXSocket.pair
      input, = IO.pipe
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::ERROR, 'bad or missing token'))
      err = StringIO.new
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new, error: err)
      request = SpiceClient::Request.new(argv: ['show'], terminal: terminal, token: '')
      Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }

      expect(err.string).to include('bad or missing token')
    end

    it 'exits non-zero after an error frame, so a script notices' do
      mine, theirs = UNIXSocket.pair
      input, = IO.pipe
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::ERROR, 'nope'))
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new, error: StringIO.new)
      request = SpiceClient::Request.new(argv: ['show'], terminal: terminal, token: '')

      expect(Timeout.timeout(5) { described_class.new(mine, terminal).run(request) }).to eq(1)
    end

    it 'refuses to invent an exit code when the connection just dies' do
      mine, theirs = UNIXSocket.pair
      input, = IO.pipe
      theirs.close
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      request = SpiceClient::Request.new(argv: ['show'], terminal: terminal, token: '')

      expect { Timeout.timeout(5) { described_class.new(mine, terminal).run(request) } }
        .to raise_error(SpiceClient::Failure, /without an exit code/)
    end
  end

  describe '#handle' do
    it 'writes data to the terminal' do
      out = StringIO.new
      terminal = SpiceClient::Terminal.new(output: out)
      session = described_class.new(UNIXSocket.pair.first, terminal)

      session.handle(SpiceWire::Frame::DATA, 'output')

      expect(out.string).to eq('output')
    end

    it 'records the exit code' do
      session = described_class.new(UNIXSocket.pair.first, SpiceClient::Terminal.new(output: StringIO.new))

      session.handle(SpiceWire::Frame::EXIT, '7')

      expect(session.exit_code).to eq(7)
    end

    it 'ignores a frame type only the client is supposed to send' do
      session = described_class.new(UNIXSocket.pair.first, SpiceClient::Terminal.new(output: StringIO.new))

      session.handle(SpiceWire::Frame::RESIZE, '40 132')

      expect(session.exit_code).to be_nil
    end

    it 'ignores an unknown frame type, so a newer server cannot crash it' do
      session = described_class.new(UNIXSocket.pair.first, SpiceClient::Terminal.new(output: StringIO.new))

      expect { session.handle(99, 'whatever') }.not_to raise_error
    end
  end

  describe '#finished?' do
    it 'is false before the server has reported anything' do
      session = described_class.new(UNIXSocket.pair.first, SpiceClient::Terminal.new(output: StringIO.new))

      expect(session.finished?).to be(false)
    end

    it 'is true once an exit code has arrived' do
      session = described_class.new(UNIXSocket.pair.first, SpiceClient::Terminal.new(output: StringIO.new))
      session.handle(SpiceWire::Frame::EXIT, '0')

      expect(session.finished?).to be(true)
    end

    it 'is true for exit code zero, not just a non-zero one' do
      session = described_class.new(UNIXSocket.pair.first, SpiceClient::Terminal.new(output: StringIO.new))
      session.handle(SpiceWire::Frame::EXIT, '0')

      expect(session.exit_code).to eq(0)
    end
  end

  describe '#watched' do
    it 'watches both the connection and stdin while input is still open' do
      input, = IO.pipe
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      session = described_class.new(UNIXSocket.pair.first, terminal)

      expect(session.watched).to include(input)
    end

    it 'stops watching stdin once it has run out' do
      input, input_writer = IO.pipe
      input_writer.close
      terminal = SpiceClient::Terminal.new(input: input, output: StringIO.new)
      session = described_class.new(UNIXSocket.pair.first, terminal)
      session.forward_input

      expect(session.watched).not_to include(input)
    end
  end

  describe '#server_done?' do
    it 'is false once the server has gone' do
      mine, theirs = UNIXSocket.pair
      theirs.close
      session = described_class.new(mine, SpiceClient::Terminal.new(output: StringIO.new))

      expect(session.server_done?).to be(true)
    end

    it 'is false once an exit code has arrived, so the loop stops' do
      mine, theirs = UNIXSocket.pair
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '0'))
      session = described_class.new(mine, SpiceClient::Terminal.new(output: StringIO.new))

      expect(session.server_done?).to be(true)
    end

    it 'is true while output is still arriving' do
      mine, theirs = UNIXSocket.pair
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'more'))
      session = described_class.new(mine, SpiceClient::Terminal.new(output: StringIO.new))

      expect(session.server_done?).to be(false)
    end
  end
end

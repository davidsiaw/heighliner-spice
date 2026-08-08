# frozen_string_literal: true

RSpec.describe Spice::Session do
  describe '#run' do
    it 'sends the command output back as data frames' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['show'], 'cwd' => __dir__)}\n")

      frames = frames_until_end(client)

      expect(output_of(frames)).to include('argv=[show]')
    end

    it 'ends with the exit code of the command' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['show'], 'cwd' => __dir__)}\n")

      frames = frames_until_end(client)

      expect(frame_payload(frames, SpiceWire::Frame::EXIT)).to eq('7')
    end

    it 'reports a rejected request as an error frame rather than a crash' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['show'], 'cwd' => '/no/such/place')}\n")

      frames = frames_until_end(client)

      expect(frame_payload(frames, SpiceWire::Frame::ERROR)).to include('does not exist on the spice server')
    end

    it 'rejects a bad token before running anything' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('token' => 'wrong', 'argv' => ['show'], 'cwd' => __dir__)}\n")

      frames = frames_until_end(client)

      expect(frame_payload(frames, SpiceWire::Frame::ERROR)).to eq('bad or missing token')
    end

    it 'sends no exit frame when the request never ran' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("not json\n")

      frames = frames_until_end(client)

      expect(frame_payload(frames, SpiceWire::Frame::EXIT)).to be_nil
    end

    it 'reports an unexpected failure as an error frame naming the class' do
      allow(Spice::Config).to receive(:token).and_return('')
      allow(Spice::Command).to receive(:new).and_raise(TypeError, 'boom')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['show'], 'cwd' => __dir__)}\n")

      frames = frames_until_end(client)

      expect(frame_payload(frames, SpiceWire::Frame::ERROR)).to eq('spice: TypeError: boom')
    end

    it 'closes the socket when it is finished' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      thread = Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['show'], 'cwd' => __dir__)}\n")
      frames_until_end(client)
      thread.join

      expect(server).to be_closed
    end

    it 'delivers a data frame to the command as stdin' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['readline'], 'cwd' => __dir__)}\n")
      client.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, "typed\n"))

      frames = frames_until_end(client)

      expect(output_of(frames)).to include('got=typed')
    end

    it 'strips carriage returns for a client that is not a terminal' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['show'], 'cwd' => __dir__, 'tty' => false)}\n")

      frames = frames_until_end(client)

      expect(output_of(frames)).not_to include("\r")
    end

    it 'kills the command when the client disconnects, so nothing is orphaned' do
      allow(Spice::Config).to receive(:token).and_return('')
      server, client = UNIXSocket.pair
      thread = Thread.new { described_class.new(server, program: FAKE_HEIGHLINER).run }
      client.write("#{JSON.generate('argv' => ['sleeper'], 'cwd' => __dir__)}\n")
      sleep 0.3
      client.close

      expect { thread.join(5) }.to change(thread, :status).to(false)
    end
  end

  describe '#dispatch' do
    it 'writes a data frame to the command as stdin' do
      command = instance_double(Spice::Command)
      session = described_class.new(UNIXSocket.pair.first)
      allow(command).to receive(:write)

      session.dispatch(command, SpiceWire::Frame::DATA, 'keystrokes')

      expect(command).to have_received(:write).with('keystrokes')
    end

    it 'turns a stdin-eof frame into end of input' do
      command = instance_double(Spice::Command)
      session = described_class.new(UNIXSocket.pair.first)
      allow(command).to receive(:end_input)

      session.dispatch(command, SpiceWire::Frame::STDIN_EOF, '')

      expect(command).to have_received(:end_input)
    end

    it 'splits a resize payload into rows and columns' do
      command = instance_double(Spice::Command)
      session = described_class.new(UNIXSocket.pair.first)
      allow(command).to receive(:resize)

      session.dispatch(command, SpiceWire::Frame::RESIZE, '40 132')

      expect(command).to have_received(:resize).with('40', '132')
    end

    it 'ignores a frame type only the server is supposed to send' do
      command = instance_double(Spice::Command)
      session = described_class.new(UNIXSocket.pair.first)

      expect { session.dispatch(command, SpiceWire::Frame::EXIT, '0') }.not_to raise_error
    end

    it 'ignores an unknown frame type, so a newer client cannot crash it' do
      command = instance_double(Spice::Command)
      session = described_class.new(UNIXSocket.pair.first)

      expect { session.dispatch(command, 99, 'whatever') }.not_to raise_error
    end
  end

  describe '#send_frame' do
    it 'writes a framed message to the socket' do
      server, client = UNIXSocket.pair
      session = described_class.new(server)

      session.send_frame(SpiceWire::Frame::DATA, 'hello')

      expect(client.readpartial(64)).to eq(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'hello'))
    end

    it 'ignores a write to a socket whose client has gone' do
      server, client = UNIXSocket.pair
      client.close
      session = described_class.new(server)
      session.send_frame(SpiceWire::Frame::DATA, 'first')

      expect { session.send_frame(SpiceWire::Frame::DATA, 'second') }.not_to raise_error
    end
  end

  describe '#close' do
    it 'closes the socket' do
      server, = UNIXSocket.pair
      session = described_class.new(server)

      session.close

      expect(server).to be_closed
    end

    it 'is safe to call twice' do
      server, = UNIXSocket.pair
      session = described_class.new(server)
      session.close

      expect { session.close }.not_to raise_error
    end
  end

  describe '#command_finished?' do
    it 'is false once the command has closed its end' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)
      command = Spice::Command.new(request, program: FAKE_HEIGHLINER).start
      read_until_eof(command.reader)
      session = described_class.new(UNIXSocket.pair.first)

      expect(session.command_finished?(command)).to be(true)
    end
  end

  describe '#client_gone?' do
    it 'is false once the client has gone' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__)
      command = Spice::Command.new(request, program: FAKE_HEIGHLINER).start
      server, client = UNIXSocket.pair
      client.close

      expect(described_class.new(server).client_gone?(command)).to be(true)
    ensure
      command.stop
    end

    it 'is true while the client is still sending' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__)
      command = Spice::Command.new(request, program: FAKE_HEIGHLINER).start
      server, client = UNIXSocket.pair
      client.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'x'))

      expect(described_class.new(server).client_gone?(command)).to be(false)
    ensure
      command.stop
    end
  end
end

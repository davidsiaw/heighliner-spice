# frozen_string_literal: true

RSpec.describe Spice::Command do
  describe '#start' do
    it 'runs the program with the argv the client sent' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => %w[show hello], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include('argv=[show hello]')
    end

    it 'runs the program in the directory the client sent' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include("cwd=#{__dir__}")
    end

    it 'passes argv as separate words, so a space cannot become two arguments' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['db_load', 'my save'], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include('argv=[db_load my save]')
    end

    it 'keeps a shell metacharacter inside one argument instead of splitting on it' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show; echo pwned'], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include('argv=[show; echo pwned]')
    end

    it 'never executes an injected command' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show; echo pwned'], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).not_to match(/^pwned$/)
    end

    it 'does not expand a variable reference in argv' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show', '$HOME'], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include('argv=[show $HOME]')
    end

    it 'does not treat a cwd containing a space as two arguments' do
      allow(Spice::Config).to receive(:token).and_return('')
      dir = File.join(Dir.mktmpdir, 'a b')
      Dir.mkdir(dir)
      request = Spice::Request.new('argv' => ['show'], 'cwd' => dir)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include("cwd=#{dir}")
    end

    it 'suppresses carriage returns for a client that is not a terminal' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__, 'tty' => false)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).not_to include("\r")
    end

    it 'leaves the line discipline alone for a client that is a terminal' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__, 'tty' => true)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include("\r\n")
    end

    it 'gives the program the window size the client reported' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['winsize'], 'cwd' => __dir__, 'tty' => true, 'rows' => 40, 'cols' => 132 }
      request = Spice::Request.new(header)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(read_until_eof(command.reader)).to include('size=40 132')
    end

    it 'forwards the allowlisted environment to the program' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)

      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      read_until_eof(command.reader)

      expect(request.env).to have_key('CONTEXT_DIR')
    end

    it 'returns itself so the caller can chain' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER)

      expect(command.start).to be(command)
    end
  end

  describe '#write' do
    it 'delivers stdin to the program' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['readline'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      command.write("typed\n")

      expect(read_until_eof(command.reader)).to include('got=typed')
    end

    it 'ignores a write to a program that has already exited' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      read_until_eof(command.reader)
      command.stop

      expect { command.write('anything') }.not_to raise_error
    end
  end

  describe '#end_input' do
    it 'sends the end-of-input character a terminal would' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      allow(command).to receive(:write)

      command.end_input

      expect(command).to have_received(:write).with("\x04")
    end
  end

  describe '#resize' do
    it 'applies a new window size' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__, 'tty' => true)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      command.resize(50, 100)

      expect(command.reader.winsize).to eq([50, 100])
    ensure
      command.stop
    end

    it 'accepts strings, because resize frames arrive as text' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__, 'tty' => true)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      command.resize('50', '100')

      expect(command.reader.winsize).to eq([50, 100])
    ensure
      command.stop
    end

    it 'ignores a zero size, which is what a client with no terminal reports' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__, 'tty' => true)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      command.resize(50, 100)

      command.resize(0, 0)

      expect(command.reader.winsize).to eq([50, 100])
    ensure
      command.stop
    end

    it 'ignores a negative size' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__, 'tty' => true)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      command.resize(50, 100)

      command.resize(-1, -1)

      expect(command.reader.winsize).to eq([50, 100])
    ensure
      command.stop
    end

    it 'ignores garbage rather than killing the session' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__, 'tty' => true)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect { command.resize('wide', 'tall') }.not_to raise_error
    ensure
      command.stop
    end
  end

  describe '#stop' do
    it 'returns the exit code of a program that finished on its own' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      read_until_eof(command.reader)

      expect(command.stop).to eq(7)
    end

    it 'reports a signalled program as 128 plus the signal, as a shell would' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start

      expect(command.stop).to eq(143)
    end

    it 'ends a program that is still running, so nothing is orphaned' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['sleeper'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      pid = command.pid
      command.stop

      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end

    it 'closes the pty so the descriptors are not leaked' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = Spice::Request.new('argv' => ['show'], 'cwd' => __dir__)
      command = described_class.new(request, program: FAKE_HEIGHLINER).start
      read_until_eof(command.reader)
      command.stop

      expect(command.reader).to be_closed
    end
  end
end

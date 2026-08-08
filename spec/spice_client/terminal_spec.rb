# frozen_string_literal: true

RSpec.describe SpiceClient::Terminal do
  describe '#tty?' do
    it 'is false when output is redirected, which is how an agent runs it' do
      expect(described_class.new(output: StringIO.new).tty?).to be(false)
    end

    it 'is true on a real terminal' do
      primary, secondary = PTY.open

      expect(described_class.new(output: secondary).tty?).to be(true)
    ensure
      primary.close
      secondary.close
    end
  end

  describe '#size' do
    it 'is zero by zero with no terminal, which tells the server not to resize' do
      expect(described_class.new(output: StringIO.new).size).to eq([0, 0])
    end

    it 'reports the window size of a real terminal' do
      primary, secondary = PTY.open
      secondary.winsize = [40, 132]

      expect(described_class.new(output: secondary).size).to eq([40, 132])
    ensure
      primary.close
      secondary.close
    end

    it 'is zero by zero when the terminal refuses to answer' do
      primary, secondary = PTY.open
      terminal = described_class.new(output: secondary)
      allow(secondary).to receive(:winsize).and_raise(Errno::ENOTTY)

      expect(terminal.size).to eq([0, 0])
    ensure
      primary.close
      secondary.close
    end
  end

  describe '#raw' do
    it 'runs the block when there is no terminal to put into raw mode' do
      ran = false

      described_class.new(input: StringIO.new).raw { ran = true }

      expect(ran).to be(true)
    end

    it 'returns the value of the block' do
      expect(described_class.new(input: StringIO.new).raw { 42 }).to eq(42)
    end

    it 'puts a real terminal into raw mode so ^C reaches the far end' do
      primary, secondary = PTY.open
      terminal = described_class.new(input: secondary)
      allow(secondary).to receive(:raw).and_yield

      terminal.raw { nil }

      expect(secondary).to have_received(:raw)
    ensure
      primary.close
      secondary.close
    end
  end

  describe '#on_resize' do
    it 'reports the new size when the window changes' do
      primary, secondary = PTY.open
      secondary.winsize = [24, 80]
      reported = nil
      described_class.new(output: secondary).on_resize { |rows, cols| reported = [rows, cols] }

      Process.kill('WINCH', Process.pid)
      sleep 0.1

      expect(reported).to eq([24, 80])
    ensure
      trap('WINCH', 'DEFAULT')
      primary.close
      secondary.close
    end

    it 'stays quiet when there is no terminal, so nothing is sent for a zero size' do
      reported = :untouched
      described_class.new(output: StringIO.new).on_resize { |rows, cols| reported = [rows, cols] }

      Process.kill('WINCH', Process.pid)
      sleep 0.1

      expect(reported).to eq(:untouched)
    ensure
      trap('WINCH', 'DEFAULT')
    end

    it 'swallows a failure rather than killing the process from a signal handler' do
      terminal = described_class.new(output: StringIO.new)
      allow(terminal).to receive(:size).and_raise(IOError)
      terminal.on_resize { nil }

      expect { Process.kill('WINCH', Process.pid) && sleep(0.1) }.not_to raise_error
    ensure
      trap('WINCH', 'DEFAULT')
    end
  end

  describe '#write' do
    it 'writes to the output stream' do
      out = StringIO.new

      described_class.new(output: out).write('hello')

      expect(out.string).to eq('hello')
    end

    it 'flushes, so output appears as it arrives instead of at the end' do
      out = StringIO.new
      allow(out).to receive(:flush)

      described_class.new(output: out).write('hello')

      expect(out).to have_received(:flush)
    end
  end

  describe '#warn' do
    it 'writes to the error stream, keeping it out of captured output' do
      err = StringIO.new

      described_class.new(error: err).warn('something went wrong')

      expect(err.string).to eq("something went wrong\n")
    end
  end

  describe '#readable' do
    it 'exposes the input stream so a session can select on it' do
      input = StringIO.new

      expect(described_class.new(input: input).readable).to be(input)
    end
  end
end

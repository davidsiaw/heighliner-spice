# frozen_string_literal: true

RSpec.describe SpiceClient::Request do
  describe '#to_h' do
    it 'carries the argv the user typed' do
      request = described_class.new(argv: %w[up -v], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_h[:argv]).to eq(%w[up -v])
    end

    it 'carries the working directory, which the server must see at the same path' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_h[:cwd]).to eq(Dir.pwd)
    end

    it 'sends an absolute path, because the server has no idea what is relative to what' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_h[:cwd]).to start_with('/')
    end

    it 'carries the token' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: 'sekrit')

      expect(request.to_h[:token]).to eq('sekrit')
    end

    it 'reports no terminal when output is redirected, so the server strips carriage returns' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_h[:tty]).to be(false)
    end

    it 'reports a terminal when there is one' do
      primary, secondary = PTY.open
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: secondary), token: '')

      expect(request.to_h[:tty]).to be(true)
    ensure
      primary.close
      secondary.close
    end

    it 'reports the window size of a real terminal' do
      primary, secondary = PTY.open
      secondary.winsize = [40, 132]
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: secondary), token: '')

      expect(request.to_h.values_at(:rows, :cols)).to eq([40, 132])
    ensure
      primary.close
      secondary.close
    end

    it 'reports a zero size when there is no terminal' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_h.values_at(:rows, :cols)).to eq([0, 0])
    end
  end

  describe '#forwarded_env' do
    it 'forwards the 1Password token, which heighliner needs for certificates' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')
      allow(request).to receive(:env_var).with('OP_SERVICE_ACCOUNT_TOKEN').and_return('ops')

      expect(request.forwarded_env).to eq('OP_SERVICE_ACCOUNT_TOKEN' => 'ops')
    end

    it 'omits a variable that is not set, rather than sending an empty one' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')
      allow(request).to receive(:env_var).and_return(nil)

      expect(request.forwarded_env).to be_empty
    end
  end

  describe '#to_line' do
    it 'is a single line, because the server reads the header with gets' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_line.chomp).not_to include("\n")
    end

    it 'ends with a newline, or the server would wait forever' do
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(request.to_line).to end_with("\n")
    end

    it 'is JSON the server can parse' do
      request = described_class.new(argv: %w[up -v], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(JSON.parse(request.to_line)['argv']).to eq(%w[up -v])
    end

    it 'produces a header the server accepts' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: '')

      expect(Spice::Request.parse(request.to_line).argv).to eq(['up'])
    end

    it 'produces a header the server authenticates with a matching token' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')
      request = described_class.new(argv: ['up'], terminal: SpiceClient::Terminal.new(output: StringIO.new),
                                    token: 'sekrit')

      expect { Spice::Request.parse(request.to_line) }.not_to raise_error
    end
  end
end

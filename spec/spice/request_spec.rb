# frozen_string_literal: true

RSpec.describe Spice::Request do
  describe '.parse' do
    it 'builds a request from a header line' do
      allow(Spice::Config).to receive(:token).and_return('')
      line = JSON.generate(argv: ['up'], cwd: __dir__)

      expect(described_class.parse(line).argv).to eq(['up'])
    end

    it 'rejects a closed connection that never sent a header' do
      expect { described_class.parse(nil) }.to raise_error(Spice::Denied, 'no header')
    end

    it 'rejects a header that is not JSON' do
      expect { described_class.parse('not json') }.to raise_error(Spice::Denied, /malformed header/)
    end

    it 'rejects a JSON document that is not an object' do
      expect { described_class.parse('[]') }.to raise_error(Spice::Denied, 'header is not an object')
    end

    it 'rejects a bare JSON scalar' do
      expect { described_class.parse('42') }.to raise_error(Spice::Denied, 'header is not an object')
    end
  end

  describe '#authorize!' do
    it 'accepts any token when the server has none configured' do
      allow(Spice::Config).to receive(:token).and_return('')

      expect { described_class.new('argv' => ['up'], 'cwd' => __dir__) }.not_to raise_error
    end

    it 'accepts a matching token' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')

      expect { described_class.new('token' => 'sekrit', 'argv' => ['up'], 'cwd' => __dir__) }.not_to raise_error
    ensure
      allow(Spice::Config).to receive(:token).and_return('')
    end

    it 'rejects a wrong token of the same length' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')
      header = { 'token' => 'sekret', 'argv' => ['up'], 'cwd' => __dir__ }

      expect { described_class.new(header) }.to raise_error(Spice::Denied, 'bad or missing token')
    ensure
      allow(Spice::Config).to receive(:token).and_return('')
    end

    it 'rejects a token of a different length' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')
      header = { 'token' => 'no', 'argv' => ['up'], 'cwd' => __dir__ }

      expect { described_class.new(header) }.to raise_error(Spice::Denied, 'bad or missing token')
    ensure
      allow(Spice::Config).to receive(:token).and_return('')
    end

    it 'rejects a missing token' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')

      expect { described_class.new('argv' => ['up'], 'cwd' => __dir__) }.to raise_error(Spice::Denied)
    ensure
      allow(Spice::Config).to receive(:token).and_return('')
    end

    it 'checks the token before anything else, so a stranger learns nothing about the filesystem' do
      allow(Spice::Config).to receive(:token).and_return('sekrit')
      header = { 'token' => 'wrong', 'argv' => [], 'cwd' => '/no/such/place' }

      expect { described_class.new(header) }.to raise_error(Spice::Denied, 'bad or missing token')
    ensure
      allow(Spice::Config).to receive(:token).and_return('')
    end
  end

  describe '#validate!' do
    it 'rejects an empty argv' do
      allow(Spice::Config).to receive(:token).and_return('')

      expect { described_class.new('argv' => [], 'cwd' => __dir__) }.to raise_error(Spice::Denied, 'no argv')
    end

    it 'rejects a missing argv' do
      allow(Spice::Config).to receive(:token).and_return('')

      expect { described_class.new('cwd' => __dir__) }.to raise_error(Spice::Denied, 'no argv')
    end

    it 'rejects a cwd the server cannot see' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => '/no/such/place' }

      expect { described_class.new(header) }.to raise_error(Spice::Denied, %r{/no/such/place})
    end

    it 'explains that the mount is the problem, because the agent cannot see host paths' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => '/no/such/place' }

      expect { described_class.new(header) }.to raise_error(Spice::Denied, /mounted at the same absolute path/)
    end

    it 'rejects a file used as a cwd' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => __FILE__ }

      expect { described_class.new(header) }.to raise_error(Spice::Denied)
    end
  end

  describe '#tty?' do
    it 'is true when the client says it is a terminal' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = described_class.new('argv' => ['up'], 'cwd' => __dir__, 'tty' => true)

      expect(request.tty?).to be(true)
    end

    it 'is false when the client says it is not' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = described_class.new('argv' => ['up'], 'cwd' => __dir__, 'tty' => false)

      expect(request.tty?).to be(false)
    end

    it 'is false when the client omits it, so output is not littered with carriage returns' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = described_class.new('argv' => ['up'], 'cwd' => __dir__)

      expect(request.tty?).to be(false)
    end
  end

  describe '#build_env' do
    it 'forwards an allowlisted variable sent by the client' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => __dir__, 'env' => { 'OP_SERVICE_ACCOUNT_TOKEN' => 'ops' } }

      expect(described_class.new(header).env).to include('OP_SERVICE_ACCOUNT_TOKEN' => 'ops')
    end

    it 'falls back to the server environment when the client omits it' do
      allow(Spice::Config).to receive(:token).and_return('')
      request = described_class.new('argv' => ['up'], 'cwd' => __dir__)
      allow(request).to receive(:env_var).with('OP_SERVICE_ACCOUNT_TOKEN').and_return('from-server')

      expect(request.build_env['OP_SERVICE_ACCOUNT_TOKEN']).to eq('from-server')
    end

    it 'drops anything not on the allowlist, so a sandbox cannot choose what runs' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => __dir__, 'env' => { 'PATH' => '/evil' } }

      expect(described_class.new(header).env).not_to have_key('PATH')
    end

    it 'sets CONTEXT_DIR, which heighliner uses to stage 1Password certificates' do
      allow(Spice::Config).to receive(:token).and_return('')

      expect(described_class.new('argv' => ['up'], 'cwd' => __dir__).env['CONTEXT_DIR']).to eq(__dir__)
    end

    it 'ignores an env field that is not an object' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => __dir__, 'env' => 'not-a-hash' }

      expect(described_class.new(header).env).to have_key('CONTEXT_DIR')
    end

    it 'stringifies a forwarded value, because JSON can carry numbers' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => __dir__, 'env' => { 'OP_SERVICE_ACCOUNT_TOKEN' => 42 } }

      expect(described_class.new(header).env['OP_SERVICE_ACCOUNT_TOKEN']).to eq('42')
    end
  end

  describe '#initialize' do
    it 'stringifies argv, because JSON can carry numbers' do
      allow(Spice::Config).to receive(:token).and_return('')

      expect(described_class.new('argv' => ['db_load', 5], 'cwd' => __dir__).argv).to eq(%w[db_load 5])
    end

    it 'defaults rows to zero when the client has no terminal' do
      allow(Spice::Config).to receive(:token).and_return('')

      expect(described_class.new('argv' => ['up'], 'cwd' => __dir__).rows).to eq(0)
    end

    it 'reads the window size the client reported' do
      allow(Spice::Config).to receive(:token).and_return('')
      header = { 'argv' => ['up'], 'cwd' => __dir__, 'rows' => 40, 'cols' => 132 }

      expect(described_class.new(header).cols).to eq(132)
    end
  end
end

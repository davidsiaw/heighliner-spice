# frozen_string_literal: true

RSpec.describe SpiceClient::Endpoint do
  describe '#initialize' do
    it 'takes the host out of SPICE_URL, which names the health endpoint' do
      expect(described_class.new(url: 'http://heighliner-spice:7529').host).to eq('heighliner-spice')
    end

    it 'ignores the port in SPICE_URL, because the stream listens elsewhere' do
      expect(described_class.new(url: 'http://heighliner-spice:7529').port).to eq(7530)
    end

    it 'accepts a bare hostname that is not a URL' do
      expect(described_class.new(url: 'heighliner-spice').host).to eq('heighliner-spice')
    end

    it 'reads SPICE_STREAM_PORT' do
      expect(described_class.new(url: 'spice', port: '9000').port).to eq(9000)
    end

    it 'refuses to guess when there is no url' do
      expect { described_class.new(url: nil) }.to raise_error(SpiceClient::Failure, /SPICE_URL is not set/)
    end

    it 'refuses an empty url, which is what docker supplies for -e SPICE_URL=' do
      expect { described_class.new(url: '') }.to raise_error(SpiceClient::Failure, /SPICE_URL is not set/)
    end

    it 'tells the reader the fix is on the host, since a sandbox cannot start spice' do
      expect { described_class.new(url: '') }.to raise_error(SpiceClient::Failure, /sp up/)
    end
  end

  describe '.from_env' do
    it 'reads the host from SPICE_URL' do
      allow(described_class).to receive(:env_var).with('SPICE_URL').and_return('spice-host')
      allow(described_class).to receive(:env_var).with('SPICE_STREAM_PORT').and_return(nil)

      expect(described_class.from_env.host).to eq('spice-host')
    end

    it 'reads the port from SPICE_STREAM_PORT' do
      allow(described_class).to receive(:env_var).with('SPICE_URL').and_return('spice-host')
      allow(described_class).to receive(:env_var).with('SPICE_STREAM_PORT').and_return('9000')

      expect(described_class.from_env.port).to eq(9000)
    end

    it 'fails with the SPICE_URL message when the variable is missing' do
      allow(described_class).to receive(:env_var).and_return(nil)

      expect { described_class.from_env }.to raise_error(SpiceClient::Failure, /SPICE_URL is not set/)
    end
  end

  describe '.stream_port' do
    it 'defaults to 7530' do
      expect(described_class.stream_port(nil)).to eq(7530)
    end

    it 'treats an empty variable as unset, because docker sets one for every -e NAME=' do
      expect(described_class.stream_port('')).to eq(7530)
    end

    it 'parses a numeric value' do
      expect(described_class.stream_port('9000')).to eq(9000)
    end

    it 'raises on a non-numeric value rather than connecting somewhere unexpected' do
      expect { described_class.stream_port('stream') }.to raise_error(ArgumentError)
    end
  end

  describe '#connect' do
    it 'returns a connected socket' do
      server = TCPServer.new('127.0.0.1', 0)
      endpoint = described_class.new(url: '127.0.0.1', port: server.addr[1].to_s)

      expect(endpoint.connect).to be_a(TCPSocket)
    ensure
      server.close
    end

    it 'turns a refused connection into a message about starting the server' do
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1].to_s
      server.close
      endpoint = described_class.new(url: '127.0.0.1', port: port)

      expect { endpoint.connect }.to raise_error(SpiceClient::Failure, /cannot reach the spice server/)
    end

    it 'names the host and port it tried, so the reader can check them' do
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1].to_s
      server.close
      endpoint = described_class.new(url: '127.0.0.1', port: port)

      expect { endpoint.connect }.to raise_error(SpiceClient::Failure, /127\.0\.0\.1:#{port}/)
    end

    it 'says how to check the server, because the fix is never inside the sandbox' do
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1].to_s
      server.close
      endpoint = described_class.new(url: '127.0.0.1', port: port)

      expect { endpoint.connect }.to raise_error(SpiceClient::Failure, /sp status/)
    end

    it 'treats a name that does not resolve as the server being absent' do
      endpoint = described_class.new(url: 'no-such-spice-host.invalid', port: '7530')

      expect { endpoint.connect }.to raise_error(SpiceClient::Failure, /cannot reach the spice server/)
    end
  end
end

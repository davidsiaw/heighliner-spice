# frozen_string_literal: true

RSpec.describe Spice::Config do
  describe '.port' do
    it 'returns the default when the variable is unset' do
      allow(described_class).to receive(:env_var).with('SPICE_TEST_PORT').and_return(nil)

      expect(described_class.port('SPICE_TEST_PORT', 1234)).to eq(1234)
    end

    it 'treats an empty variable as unset, because docker sets one for every -e NAME=' do
      allow(described_class).to receive(:env_var).with('SPICE_TEST_PORT').and_return('')

      expect(described_class.port('SPICE_TEST_PORT', 1234)).to eq(1234)
    end

    it 'parses a numeric value' do
      allow(described_class).to receive(:env_var).with('SPICE_TEST_PORT').and_return('4321')

      expect(described_class.port('SPICE_TEST_PORT', 1234)).to eq(4321)
    end

    it 'raises on a non-numeric value rather than listening somewhere unexpected' do
      allow(described_class).to receive(:env_var).with('SPICE_TEST_PORT').and_return('https')

      expect { described_class.port('SPICE_TEST_PORT', 1234) }.to raise_error(ArgumentError)
    end
  end

  describe '.health_port' do
    it 'defaults to 7529' do
      allow(described_class).to receive(:env_var).with('SPICE_PORT').and_return(nil)

      expect(described_class.health_port).to eq(7529)
    end

    it 'reads SPICE_PORT' do
      allow(described_class).to receive(:env_var).with('SPICE_PORT').and_return('9001')

      expect(described_class.health_port).to eq(9001)
    end
  end

  describe '.stream_port' do
    it 'defaults to 7530' do
      allow(described_class).to receive(:env_var).with('SPICE_STREAM_PORT').and_return(nil)

      expect(described_class.stream_port).to eq(7530)
    end

    it 'reads SPICE_STREAM_PORT' do
      allow(described_class).to receive(:env_var).with('SPICE_STREAM_PORT').and_return('9002')

      expect(described_class.stream_port).to eq(9002)
    end

    it 'differs from the health port by default, so the two listeners can coexist' do
      allow(described_class).to receive(:env_var).and_return(nil)

      expect(described_class.stream_port).not_to eq(described_class.health_port)
    end
  end

  describe '.token' do
    it 'is empty when SPICE_TOKEN is unset' do
      allow(described_class).to receive(:env_var).with('SPICE_TOKEN').and_return(nil)

      expect(described_class.token).to eq('')
    end

    it 'reads SPICE_TOKEN' do
      allow(described_class).to receive(:env_var).with('SPICE_TOKEN').and_return('sekrit')

      expect(described_class.token).to eq('sekrit')
    end
  end

  describe '.authenticated?' do
    it 'is false with no token, which is what makes the server warn on boot' do
      allow(described_class).to receive(:env_var).with('SPICE_TOKEN').and_return(nil)

      expect(described_class.authenticated?).to be(false)
    end

    it 'is false for an empty token, so a failed token write cannot open the server up' do
      allow(described_class).to receive(:env_var).with('SPICE_TOKEN').and_return('')

      expect(described_class.authenticated?).to be(false)
    end

    it 'is true once a token is set' do
      allow(described_class).to receive(:env_var).with('SPICE_TOKEN').and_return('sekrit')

      expect(described_class.authenticated?).to be(true)
    end
  end

  describe '::ENV_ALLOWLIST' do
    it 'forwards the 1Password token heighliner needs for certificates' do
      expect(described_class::ENV_ALLOWLIST).to include('OP_SERVICE_ACCOUNT_TOKEN')
    end

    it 'does not forward PATH, which would let a sandbox choose what runs' do
      expect(described_class::ENV_ALLOWLIST).not_to include('PATH')
    end

    it 'is frozen, so no request can extend it at runtime' do
      expect(described_class::ENV_ALLOWLIST).to be_frozen
    end
  end
end

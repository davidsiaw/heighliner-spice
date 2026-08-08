# frozen_string_literal: true

RSpec.describe SpiceClient do
  describe '.main' do
    it 'returns the exit code of the command' do
      allow(described_class).to receive(:run).and_return(7)

      expect(described_class.main(['show'], warner: StringIO.new)).to eq(7)
    end

    it 'turns a failure the user must act on into exit 1' do
      allow(described_class).to receive(:run).and_raise(SpiceClient::Failure, 'no server')

      expect(described_class.main(['show'], warner: StringIO.new)).to eq(1)
    end

    it 'prints the failure message rather than a backtrace' do
      allow(described_class).to receive(:run).and_raise(SpiceClient::Failure, 'SPICE_URL is not set')
      warner = StringIO.new

      described_class.main(['show'], warner: warner)

      expect(warner.string).to include('SPICE_URL is not set')
    end

    it 'reports an interrupt the way a shell does' do
      allow(described_class).to receive(:run).and_raise(Interrupt)

      expect(described_class.main(['show'], warner: StringIO.new)).to eq(130)
    end

    it 'lets an unexpected error through, because hiding it would help nobody' do
      allow(described_class).to receive(:run).and_raise(TypeError, 'boom')

      expect { described_class.main(['show'], warner: StringIO.new) }.to raise_error(TypeError)
    end
  end

  describe '.run' do
    it 'fails with the SPICE_URL message when no server is configured' do
      allow(SpiceClient::Endpoint).to receive(:from_env).and_raise(SpiceClient::Failure, 'SPICE_URL is not set')

      expect { described_class.run(['show']) }.to raise_error(SpiceClient::Failure, /SPICE_URL is not set/)
    end
  end
end

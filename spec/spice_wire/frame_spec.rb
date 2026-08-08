# frozen_string_literal: true

RSpec.describe SpiceWire::Frame do
  describe '.pack' do
    it 'prefixes the type and a big-endian length' do
      expect(described_class.pack(described_class::EXIT, '7')).to eq("\x02\x00\x00\x00\x01".b + '7'.b)
    end

    it 'defaults to an empty payload' do
      expect(described_class.pack(described_class::STDIN_EOF)).to eq("\x01\x00\x00\x00\x00".b)
    end

    it 'measures bytes rather than characters' do
      expect(described_class.pack(described_class::DATA, 'é').unpack1('@1N')).to eq(2)
    end

    it 'produces binary output, so frames can be concatenated' do
      expect(described_class.pack(described_class::DATA, 'é').encoding).to eq(Encoding::BINARY)
    end
  end

  describe '.drain' do
    it 'yields a complete frame' do
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, 'hello')
      yielded = []

      described_class.drain(buffer) { |type, payload| yielded << [type, payload] }

      expect(yielded).to eq([[described_class::DATA, 'hello']])
    end

    it 'consumes the frame it yielded' do
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, 'hello')

      described_class.drain(buffer) { nil }

      expect(buffer).to be_empty
    end

    it 'yields every complete frame in one pass' do
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, 'a')
      buffer << described_class.pack(described_class::EXIT, '3')
      types = []

      described_class.drain(buffer) { |type, _payload| types << type }

      expect(types).to eq([described_class::DATA, described_class::EXIT])
    end

    it 'yields nothing for a partial frame' do
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, 'hello').byteslice(0, 7)
      yielded = []

      described_class.drain(buffer) { |type, payload| yielded << [type, payload] }

      expect(yielded).to be_empty
    end

    it 'leaves a partial frame in the buffer for the next read' do
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, 'hello').byteslice(0, 7)

      described_class.drain(buffer) { nil }

      expect(buffer.bytesize).to eq(7)
    end

    it 'yields a frame split across two reads once the rest arrives' do
      whole = described_class.pack(described_class::DATA, 'hello')
      buffer = described_class.buffer
      buffer << whole.byteslice(0, 7)
      described_class.drain(buffer) { raise 'must not yield a partial frame' }
      buffer << whole.byteslice(7, whole.bytesize - 7)
      yielded = []

      described_class.drain(buffer) { |type, payload| yielded << [type, payload] }

      expect(yielded).to eq([[described_class::DATA, 'hello']])
    end

    it 'keeps a trailing partial frame after consuming a whole one' do
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, 'a')
      buffer << described_class.pack(described_class::DATA, 'hello').byteslice(0, 6)

      described_class.drain(buffer) { nil }

      expect(buffer.bytesize).to eq(6)
    end

    it 'does nothing with a buffer shorter than a header' do
      buffer = described_class.buffer
      buffer << "\x00\x00"

      expect { |probe| described_class.drain(buffer, &probe) }.not_to yield_control
    end

    it 'round-trips a payload containing the bytes used for framing' do
      payload = "\x00\x01\x02\x03\x04\xFF".b
      buffer = described_class.buffer
      buffer << described_class.pack(described_class::DATA, payload)
      got = nil

      described_class.drain(buffer) { |_type, bytes| got = bytes }

      expect(got).to eq(payload)
    end
  end

  describe '.buffer' do
    it 'is binary' do
      expect(described_class.buffer.encoding).to eq(Encoding::BINARY)
    end

    it 'is mutable despite the frozen string literal magic comment' do
      expect(described_class.buffer).not_to be_frozen
    end

    it 'accepts binary appends that a UTF-8 buffer would reject' do
      buffer = described_class.buffer

      buffer << 'café'.b << "\xC3\xA9".b

      expect(buffer.bytesize).to eq(7)
    end

    it 'stays binary when fed the binary reads the sessions append' do
      buffer = described_class.buffer

      buffer << 'café'.b

      expect(buffer.encoding).to eq(Encoding::BINARY)
    end

    it 'can be sliced mid-character without producing invalid data' do
      buffer = described_class.buffer
      buffer << 'café'.b

      expect(buffer.byteslice(0, 4)).to be_valid_encoding
    end

    it 'contrasts with a UTF-8 buffer, which rejects those appends outright' do
      expect { +'café' << "\xC3\xA9".b }.to raise_error(Encoding::CompatibilityError)
    end
  end
end

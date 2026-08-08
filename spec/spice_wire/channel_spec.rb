# frozen_string_literal: true

RSpec.describe SpiceWire::Channel do
  describe '#send_frame' do
    it 'writes a framed message the peer can read' do
      mine, theirs = UNIXSocket.pair

      described_class.new(mine).send_frame(SpiceWire::Frame::DATA, 'hello')

      expect(theirs.readpartial(64)).to eq(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'hello'))
    end

    it 'is true when the write lands' do
      mine, = UNIXSocket.pair

      expect(described_class.new(mine).send_frame(SpiceWire::Frame::DATA, 'hello')).to be(true)
    end

    it 'is false once the peer has gone, rather than raising' do
      mine, theirs = UNIXSocket.pair
      theirs.close
      channel = described_class.new(mine)
      channel.send_frame(SpiceWire::Frame::DATA, 'first')

      expect(channel.send_frame(SpiceWire::Frame::DATA, 'second')).to be(false)
    end

    it 'is false on a closed socket' do
      mine, = UNIXSocket.pair
      mine.close

      expect(described_class.new(mine).send_frame(SpiceWire::Frame::DATA, 'x')).to be(false)
    end
  end

  describe '#receive_frames' do
    it 'returns a frame the peer sent' do
      mine, theirs = UNIXSocket.pair
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'hello'))

      expect(described_class.new(mine).receive_frames).to eq([[SpiceWire::Frame::DATA, 'hello']])
    end

    it 'returns every frame that has arrived' do
      mine, theirs = UNIXSocket.pair
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'a'))
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::EXIT, '3'))

      expect(described_class.new(mine).receive_frames.map(&:first))
        .to eq([SpiceWire::Frame::DATA, SpiceWire::Frame::EXIT])
    end

    it 'returns nothing for a frame that has only partly arrived' do
      mine, theirs = UNIXSocket.pair
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'hello').byteslice(0, 7))

      expect(described_class.new(mine).receive_frames).to be_empty
    end

    it 'returns the frame once the rest of it arrives on a later read' do
      mine, theirs = UNIXSocket.pair
      whole = SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'hello')
      channel = described_class.new(mine)
      theirs.write(whole.byteslice(0, 7))
      channel.receive_frames
      theirs.write(whole.byteslice(7, whole.bytesize - 7))

      expect(channel.receive_frames).to eq([[SpiceWire::Frame::DATA, 'hello']])
    end

    it 'returns nothing when there is nothing to read yet' do
      mine, = UNIXSocket.pair

      expect(described_class.new(mine).receive_frames).to be_empty
    end

    it 'returns nil once the peer has gone, which is how a session knows to stop' do
      mine, theirs = UNIXSocket.pair
      theirs.close

      expect(described_class.new(mine).receive_frames).to be_nil
    end

    it 'returns nil on a closed socket' do
      mine, = UNIXSocket.pair
      mine.close

      expect(described_class.new(mine).receive_frames).to be_nil
    end

    it 'distinguishes nothing-yet from peer-gone, which the sessions depend on' do
      mine, theirs = UNIXSocket.pair
      nothing_yet = described_class.new(mine).receive_frames
      theirs.close

      expect(nothing_yet).not_to eq(described_class.new(mine).receive_frames)
    end
  end

  describe '#read_line' do
    it 'reads the JSON header the client sends before any frame' do
      mine, theirs = UNIXSocket.pair
      theirs.write("{\"argv\":[\"up\"]}\n")

      expect(described_class.new(mine).read_line).to eq("{\"argv\":[\"up\"]}\n")
    end

    it 'is nil when the peer closed without sending one' do
      mine, theirs = UNIXSocket.pair
      theirs.close

      expect(described_class.new(mine).read_line).to be_nil
    end

    it 'leaves frames written after the header for receive_frames' do
      mine, theirs = UNIXSocket.pair
      theirs.write("{}\n")
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'after'))
      channel = described_class.new(mine)
      channel.read_line

      expect(channel.receive_frames).to eq([[SpiceWire::Frame::DATA, 'after']])
    end
  end

  describe '#send_frame_line' do
    it 'writes the header verbatim, because it is not a frame' do
      mine, theirs = UNIXSocket.pair

      described_class.new(mine).send_frame_line("{\"argv\":[]}\n")

      expect(theirs.readpartial(64)).to eq("{\"argv\":[]}\n")
    end

    it 'is false once the peer has gone' do
      mine, theirs = UNIXSocket.pair
      theirs.close
      channel = described_class.new(mine)
      channel.send_frame_line("{}\n")

      expect(channel.send_frame_line("{}\n")).to be(false)
    end
  end

  describe '#to_io' do
    it 'exposes the socket so a channel can be handed to IO.select' do
      mine, = UNIXSocket.pair

      expect(described_class.new(mine).to_io).to be(mine)
    end
  end

  describe '#wait_readable' do
    it 'returns once the peer has written something' do
      mine, theirs = UNIXSocket.pair
      theirs.write(SpiceWire::Frame.pack(SpiceWire::Frame::DATA, 'x'))

      expect(described_class.new(mine).wait_readable(2)).not_to be_nil
    end

    it 'gives up after the timeout when nothing arrives' do
      mine, = UNIXSocket.pair

      expect(described_class.new(mine).wait_readable(0.1)).to be_nil
    end
  end

  describe '#close' do
    it 'closes the socket' do
      mine, = UNIXSocket.pair
      channel = described_class.new(mine)

      channel.close

      expect(channel).to be_closed
    end

    it 'is safe to call twice' do
      mine, = UNIXSocket.pair
      channel = described_class.new(mine)
      channel.close

      expect { channel.close }.not_to raise_error
    end
  end
end

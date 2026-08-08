# frozen_string_literal: true

# Shared by the server and the client. See spice/docs/protocol.md.
module SpiceWire
  # [type:uint8][length:uint32be][payload]
  module Frame
    DATA      = 0
    STDIN_EOF = 1
    EXIT      = 2
    RESIZE    = 3
    ERROR     = 4

    HEADER_BYTES = 5

    def self.pack(type, payload = '')
      [type, payload.to_s.bytesize].pack('CN') + payload.to_s.b
    end

    # Yields whole frames and removes them, leaving any partial tail in buf.
    def self.drain(buf)
      while buf.bytesize >= HEADER_BYTES
        type, len = buf.unpack('CN')
        break if buf.bytesize < HEADER_BYTES + len

        yield type, buf.byteslice(HEADER_BYTES, len)
        buf.replace(buf.byteslice(HEADER_BYTES + len, buf.bytesize - HEADER_BYTES - len))
      end
    end

    def self.buffer
      String.new(encoding: Encoding::BINARY)
    end
  end
end

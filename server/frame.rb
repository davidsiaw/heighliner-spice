# frozen_string_literal: true

module Spice
  # The wire format, shared with spice/client/heighliner.
  #
  #   [type:uint8][length:uint32be][payload]
  #
  # Both directions use the same framing; only which types are legal differs.
  module Frame
    DATA      = 0 # stdout (server->client) / stdin (client->server)
    STDIN_EOF = 1 # client->server
    EXIT      = 2 # server->client, payload is the decimal exit code
    RESIZE    = 3 # client->server, payload is "<rows> <cols>"
    ERROR     = 4 # server->client, payload is a human-readable message

    HEADER_BYTES = 5

    module_function

    def pack(type, payload = '')
      [type, payload.to_s.bytesize].pack('CN') + payload.to_s.b
    end

    # Yields every complete frame in buf and removes it, leaving any partial
    # trailing frame in place for the next read.
    def drain(buf)
      while buf.bytesize >= HEADER_BYTES
        type, len = buf.unpack('CN')
        break if buf.bytesize < HEADER_BYTES + len

        yield type, buf.byteslice(HEADER_BYTES, len)
        buf.replace(buf.byteslice(HEADER_BYTES + len, buf.bytesize - HEADER_BYTES - len))
      end
    end
  end
end

# frozen_string_literal: true

# Reading a pty raises Errno::EIO when the child closes it, which is the normal
# way a run ends rather than a failure.
module PtyReader
  def read_until_eof(io)
    out = +''
    loop { out << io.readpartial(4096) }
  rescue Errno::EIO, IOError
    out
  end
end

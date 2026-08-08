# The wire protocol

One connection runs exactly one command. There is nothing to multiplex, so
there are no stream identifiers.

## Handshake

The client opens a TCP connection and writes a single line of JSON:

```json
{"token":"...","argv":["up","-v"],"cwd":"/home/you/proj","env":{},"tty":true,"rows":40,"cols":132}
```

| Field | Meaning |
|---|---|
| `token` | shared secret; compared in constant time |
| `argv` | heighliner's arguments, as separate words |
| `cwd` | the project directory, as an absolute path the *server* must also see |
| `env` | env vars to forward; the server drops anything not on its allowlist |
| `tty` | whether the client is a terminal (see below) |
| `rows`, `cols` | initial window size, `0` when there is no terminal |

Everything the server can reject, it rejects here, before spawning anything.

## Frames

After the handshake, both directions speak the same framing:

```
[type:uint8][length:uint32be][payload]
```

Implemented once, in `spice/wire/frame.rb`, and used by both halves through
`spice/wire/channel.rb`, which owns the read buffer so that partial frames and a
vanished peer are handled in one place.

| Type | Name | Direction | Payload |
|---|---|---|---|
| 0 | `DATA` | both | stdin going forward, stdout coming back |
| 1 | `STDIN_EOF` | client to server | empty |
| 2 | `EXIT` | server to client | decimal exit code |
| 3 | `RESIZE` | client to server | `"<rows> <cols>"` |
| 4 | `ERROR` | server to client | a message written for a person to read |

A read off a socket ends wherever TCP decided, so a frame can arrive in pieces.
Both ends buffer and drain only whole frames, leaving any partial tail for the
next read.

`ERROR` and `EXIT` both end the session. `ERROR` means the command never ran.

## Buffers are binary

Accumulation buffers come from `SpiceWire::Frame.buffer`, which is
`String.new(encoding: Encoding::BINARY)` — never a `''` literal. This is not
defensive noise; a UTF-8 buffer breaks in two ways as soon as a command emits
non-ASCII output across a read boundary:

```ruby
utf8 << 'café'; utf8 << "\xC3\xA9".b   # => Encoding::CompatibilityError
'café'.byteslice(0, 4).valid_encoding? # => false
'café'.b.byteslice(0, 4).valid_encoding? # => true
```

Binary has no notion of character boundaries, so every byte sequence is valid
and slicing at arbitrary offsets is always safe.

The buffer stays binary only because everything appended to it already is —
socket reads and `Frame.pack` output. Appending a UTF-8 *literal* to an empty
binary string silently promotes the whole buffer to UTF-8, and the next binary
append then raises.

## Terminals

The server always runs heighliner on a pty. That is not a preference:

- `heighliner login` and `root` shell out to `docker exec -ti`, which requires a
  terminal to exist.
- Docker's build output and heighliner's progress dots are unbuffered only when
  they believe they are talking to a terminal.

But whether that pty should *behave* like a terminal depends on who is at the
other end, which is what the `tty` flag reports.

**Client is a terminal** (a human). The pty keeps its normal line discipline.
The client puts its own stdin in raw mode, so the local terminal stops
interpreting `^C` and the byte travels to the remote pty instead — the *remote*
process group gets SIGINT. Without raw mode, `^C` would kill the client and
orphan the command on the server. This is what makes `attach` usable.

**Client is not a terminal** (a pi agent capturing output). The server puts the
pty in raw mode instead. Otherwise the line discipline translates every `\n`
into `\r\n`, littering captured output with `^M`, and echoes back anything piped
into stdin.

`STDIN_EOF` is delivered to the pty as `\x04` (Ctrl-D), which is how a terminal
signals end of input.

## Lifecycle

The session ends when any of these happens:

| Event | Result |
|---|---|
| the child closes the pty | read raises `EOFError`/`Errno::EIO`; server sends `EXIT` |
| the client disconnects | server sends SIGTERM to the child, then reaps it |
| the request is rejected | server sends `ERROR` and closes |

Killing the child on client disconnect is deliberate. A sandbox that dies
mid-command would otherwise leave `docker run -ti` running forever with nobody
watching it. The cost is that a dropped connection aborts a long build.

Exit codes pass through unchanged. A child killed by a signal reports
`128 + signal`, so an interrupted command exits `130` exactly as it would
locally.

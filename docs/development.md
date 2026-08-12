# Working on spice

## Layout

Both halves are split the same way, and the names correspond on purpose — the
two ends of a protocol are read together.

| Server | Client | Job |
|---|---|---|
| `server.rb` | `client/heighliner` | entry point |
| `settings.rb` | `client/kaiser` | run on their own, not part of a session |
| — | `spice_client/client.rb` | `run` and `main`, so the executable is a shim |
| `server/config.rb` | — | settings read from the environment |
| `server/token.rb` | — | the shared secret, compared in constant time |
| `server/policy.rb` | — | commands a sandbox may not run |
| `server/errors.rb` (`Denied`) | `spice_client/errors.rb` (`Failure`) | the one error the other party is told about |
| `server/request.rb` | `spice_client/request.rb` | the opening header: parsed / built |
| `server/command.rb` | `spice_client/terminal.rb` | the pty / the local terminal |
| `server/session.rb` | `spice_client/session.rb` | one connection, byte shuttling |
| `server/health.rb` | — | HTTP `/health` |
| `server/listener.rb` | — | accept loop |
| `server/settings.rb`, `server/heighliner_settings.rb` | — | what heighliner calls its config dir, network and containers — see [settings.md](settings.md) |

Shared, in `wire/`:

| File | Job |
|---|---|
| `wire/frame.rb` | the frame format |
| `wire/channel.rb` | a socket that carries frames |

`Channel` is the one to reach for. `Frame` only converts bytes to frames and
back; `Channel` owns the read buffer, so partial frames, would-block reads and a
vanished peer are handled once instead of by everyone holding a socket. Before
it existed that logic was written out three times — twice in production. If you
find yourself calling `Frame.drain` outside `wire/`, that is the same mistake
starting again.

Anything both halves must agree on belongs in `wire/`, and each side aliases it
(`Frame = SpiceWire::Frame`) so call sites stay short.

`wire/` is published into the sandbox alongside the client, and the volume
mirrors the repo layout so the client's `../wire` resolves the same in both:

```
/opt/spice/client/heighliner     the executable; this directory goes on PATH
/opt/spice/client/kaiser         a wrapper for the pre-rename name
/opt/spice/client/spice_client/  client-only code
/opt/spice/wire/                 shared with the server
/opt/spice/skills/               the pi skill
```

## Comments

**Minimal comments. Make the code say it instead.**

Comments rot. They are not compiled, not tested, and nothing fails when they
stop being true — so a long explanation next to code is a promise nobody can
keep. Prefer naming and structure, which cannot silently disagree with what runs:

```ruby
return if ready.include?(command.reader) && !forward_output(command)    # before
return if ready.include?(command.reader) && command_finished?(command)  # after
```

The second needs no comment. That rename came from `Naming/PredicateMethod`,
which is worth taking seriously for this reason: a cop complaining about a name
is usually complaining about clarity.

A comment earns its place only if deleting it would be a mistake:

- a **gotcha** that looks like an error until explained —
  `# $0 is the program, $1 the directory, and the rest the arguments`
- a **constraint from outside** the file — why the pty is raw for a non-terminal
  client, why the volume layout mirrors the repo
- a **one-line class purpose**, where the class name cannot carry it alone
- a **pointer to the doc** that explains the rest — `see docs/protocol.md#terminals`

Everything longer belongs here in `docs/`. Design decisions, rationale, history,
trade-offs and anything you would want a newcomer to read *before* opening the
file: put it in a document and leave a one-line pointer at the code.

The practical test: if a comment would go stale when someone edits the three
lines beneath it, it is in the wrong place. Notes about *intent* survive edits;
notes about *mechanism* do not.

Two things this rules out. Comments that restate the code (`# increment the
counter`), and commented-out code — git remembers it, and nobody else knows
whether it is a plan or a corpse.

## When public methods pile up

Making every branchy method public (see [testing.md](testing.md)) is deliberate,
but it doubles as a design alarm.

If a class ends up with a crowd of public methods that *feel* like they should
be private — because they are not what the class is for — the visibility is not
the problem. The class is doing two jobs. The fix is to move that group into a
class of its own, and leave behind a single private memoized accessor:

```ruby
def authorize!
  return unless Config.authenticated?
  return if token.matches?(@header['token'])

  raise Denied, 'bad or missing token'
end

private

def token
  @token ||= Token.new(Config.token)
end
```

`Request` is about parsing and validating a header. Constant-time comparison and
its fallback were neither, so they are `Token`'s now. `Request` keeps one
private line, `Token` gets its own spec, and both are smaller.

The signal to watch for: you write a method, think "this shouldn't be public",
and the reason is *"it isn't really this class's business"* rather than *"it is
an implementation detail"*. The first is an extraction waiting to happen. The
second is fine — straight-line helpers stay private.

Do not do this pre-emptively. Wait until the crowd exists; a class extracted
because it might be needed one day is worse than the crowd.

## Loading

Both entry points glob their directory rather than listing requires:

```ruby
Dir.glob("#{__dir__}/server/*.rb").each { |piece| require piece }
```

This works because every reference between those files happens at call time.
Introducing a load-time dependency — a superclass in another file, or a constant
assigned from one — would silently make alphabetical order load-bearing. If that
day comes, Zeitwerk is the honest fix rather than hand-sorting requires.

## Tests

```sh
cd spice
bundle install
bundle exec rspec
bundle exec rubocop
```

Neither needs docker nor a heighliner install.

**Read [testing.md](testing.md) before writing a spec.** The rules there are not
style preferences: they cover why nothing touches `ENV`, why anything with a
branch is public, why examples inline their own setup, and why the integration
spec is the one that catches a broken `attach`.

## Changing the protocol

Client and server are published from the same image, so they cannot drift in
deployment. They can still drift in the repo. Order of work:

1. `spice/docs/protocol.md`
2. `spice/wire/`
3. `request.rb` on both sides if the header changed
4. a test that fails first

## Gotchas

**Rebuild the image after any change under `spice/`.** The client and skill are
published out of the image by `sp up`, so a stale image publishes a stale
client. `sp down && sp up` alone is not enough. Working locally, rebuild and then
`sp up`; from a pushed image, `sp update` pulls and restarts in one go.

**Accumulation buffers must be binary.** Use `SpiceWire::Frame.buffer`, never a
`''` literal. See [protocol.md](protocol.md#buffers-are-binary).

**Do not add a subcommand allowlist back.** Interactive subcommands work now,
and the token is the security boundary, not the command list.

`server/policy.rb` is not that. It is a short denylist of commands whose effect
is host-wide rather than project-local -- currently just `set`, which rewrites
the suffix and certificate source for everyone using the server. The test for
adding one is blast radius and ownership, not danger: could an agent running
this break another project, and is the decision a person's to make?

**Errors are read by agents.** A `Denied` message is sent verbatim to whoever
asked, and a pi agent will act on it. "cwd does not exist on the spice server"
tells it to stop and report; "invalid request" sends it hunting. Write the
message you would want to receive with no other context.

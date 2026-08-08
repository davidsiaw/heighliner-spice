# How spice is tested

Rules, and the reasoning behind them. They are not negotiable style preferences
picked at random — each one exists because the alternative bit us.

```sh
cd spice
bundle install
bundle exec rspec
bundle exec rubocop
```

Neither needs docker nor a heighliner install.

---

## 1. Anything with a branch is public, and is tested

A method containing a conditional, a loop, a `case`, or a **`rescue`** is part
of the surface. `private` is for straight-line helpers only.

This is why `Session`'s pump helpers, `Request`'s validation and `Command`'s
lifecycle methods are all public. They contain the decisions, so they are the
things worth asserting, and reaching them only through a public entry point
means orchestrating socket timing to test what is really a one-line decision.

The rule's purpose is that **no branch hides behind visibility**. If a method is
too internal to test directly, that is a design signal, not a reason to skip it.

It has a second use. When a class accumulates public methods that feel like they
should be private *because they are not what the class is for*, that crowd is
telling you a collaborator wants extracting — see
[development.md](development.md#when-public-methods-pile-up).

## 2. No `ENV` in specs

Every class reads the environment through one private single-purpose method:

```ruby
def self.env_var(name)
  ENV.fetch(name, nil)
end
private_class_method :env_var
```

Specs stub that:

```ruby
allow(described_class).to receive(:env_var).with('SPICE_PORT').and_return('9001')

expect(described_class.health_port).to eq(9001)
```

No mutation, no `ensure` cleanup, no leakage between examples, and it survives
`--order random` by construction rather than by remembering.

If a class gives you nowhere to stub, fix the class. `Endpoint.from_env` exists
for exactly that reason: reading the environment inside `initialize` left no
seam, and the specs had resorted to `allocate` plus `send(:initialize)`. When a
test needs a hack, the design is telling you something.

## 3. Examples inline their own setup

- No `subject`.
- No `let` — with one exception, below.
- No `context` blocks. `describe '#method'` is the only grouping needed.
- No `before` / `after` unless genuinely unavoidable.

An example should read top to bottom with nothing to scroll up for:

```ruby
it 'treats an empty variable as unset, because docker sets one for every -e NAME=' do
  allow(described_class).to receive(:env_var).with('SPICE_PORT').and_return('')

  expect(described_class.health_port).to eq(7529)
end
```

`RSpec/ExampleLength` is the **only** disabled cop, because this rule makes
examples longer on purpose.

**The exception:** an outer requirement that every example in the file needs but
which is not what any of them is about — authentication on a server `Request`,
for instance — may be stated in one line rather than reconstructed each time.
The test is whether the setup is *part of the logic under test* or merely a
precondition for reaching it.

## 4. One expectation per example

`RSpec/MultipleExpectations` stays at its default of 1. Two assertions in one
example means the second never runs when the first fails, and the name can only
describe one of them. Split it.

## 5. Name the behaviour and the reason

The example name is the documentation for the behaviour, which is why the code
itself carries almost no comments — see
[development.md](development.md#comments).

The example name should survive someone deleting the code and asking "should
this be true?".

```ruby
it 'is false for an empty token, so a failed token write cannot open the server up'
it 'kills the command when the client disconnects, so nothing is orphaned'
it 'returns nil once the peer has gone, which is how a session knows to stop'
```

Not `it 'works'`, and not `it 'returns false'` — that one restates the assertion
without saying why anyone should care.

## 6. Fakes, not mocks, for anything that carries bytes

`spec/support/bin/heighliner` is a stand-in *program*; its first argument
selects the behaviour to exercise. Everything else is real: real `PTY.spawn`,
real `UNIXSocket.pair`, real framing.

Mocking a socket or a pty would mean asserting against your own beliefs about
how they behave. Both of the transport bugs we found came from the real thing
behaving differently from the belief.

Where a spec needs to decode frames, it uses the production `SpiceWire::Channel`
rather than a second decoder. A spec helper that re-implements production logic
can drift, and then the specs pass against a protocol the real client cannot
read. `spec/support/frame_client.rb` is allowed to contain *policy* ("read until
EXIT or ERROR"); it must not contain parsing.

## 7. The integration spec is the one that matters most

`spec/integration/` runs the **real `client/heighliner` executable** as a
subprocess against a **real `server.rb`** on random free ports.

Unit specs cannot reach raw mode, signal delivery, or the exit status a shell
sees. Those only exist in a whole process. `^C` reaching the remote process
group is asserted here and nowhere else — it is the difference between `attach`
working and `attach` hanging forever, and a pipe-based test would pass happily
while it was broken.

Add to it whenever a change could plausibly break only in a real process.

## 8. Directory names follow namespaces

`spec/spice_wire/`, `spec/spice/`, `spec/spice_client/` — so
`RSpec/SpecFilePathFormat` passes with no exclusions. A spec for
`SpiceClient::Endpoint` lives at `spec/spice_client/endpoint_spec.rb`.

## 9. RuboCop runs clean, with no suppressions

No `Exclude`, no `.rubocop_todo.yml`, no inline `rubocop:disable`. The whole
config is:

```yaml
plugins:
  - rubocop-rspec

AllCops:
  TargetRubyVersion: 3.1
  NewCops: enable

RSpec/ExampleLength:
  Enabled: false
```

`NewCops: enable` is stricter than the default, not looser.

When a cop complains, assume it has a point before assuming it is noise. In this
codebase every non-mechanical offence turned out to be a real problem:
`Lint/ShadowedException` found a dead `rescue` clause, `Naming/PredicateMethod`
found three methods whose boolean return made every call site a double negative,
and `Style/Documentation` led to deleting a class that only existed to satisfy
WEBrick's naming.

---

## Writing a new spec

1. Name the file after the namespace and class.
2. `RSpec.describe TheClass do`, then one `describe '#method'` per method.
3. Inline the setup. Stub `env_var` if the environment is involved.
4. One expectation. Name it after the behaviour and the reason.
5. If it needs a real process to be meaningful, it belongs in
   `spec/integration/` as well.
6. `bundle exec rspec && bundle exec rubocop` before you are done.

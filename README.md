# Spice

Heighliner for agents that have no docker.

A `pa` sandbox has no docker socket, so an agent working in it cannot run
`heighliner up` and therefore cannot test the app it is editing. Spice is a
second container that does have the socket: the sandbox runs a stand-in
`heighliner` that forwards argv over a socket, and spice runs the real one and
proxies its terminal back.

```
[pa sandbox]                          [spice container]
  heighliner up                         heighliner up
  client/heighliner    <=socket=>       server.rb
  (stdlib ruby, no docker)              (+ /var/run/docker.sock, + a pty)
```

The connection is duplex, so `attach`, `login` and `root` work as well as `up`.

## Use

```sh
docker build -t davidsiaw/heighliner-spice spice/
sp up

cd ~/some/heighliner/project && pa
```

Inside the sandbox, `heighliner` just works. `pa` wires it up by itself whenever
a spice server is running, and behaves exactly as before when one is not.

`kaiser` works too, and so does a `~/.kaiser` config dir: heighliner used to be
called [kaiser](https://github.com/degica/kaiser), and the commands and the
config format never changed. See [settings.md](docs/settings.md).

## Docs

- [architecture.md](docs/architecture.md) — why it exists, and the path
  constraint the whole design rests on
- [settings.md](docs/settings.md) — why `sp` and `pa` ask the image what
  heighliner calls things, instead of knowing
- [protocol.md](docs/protocol.md) — the wire format, terminals, lifecycle
- [operations.md](docs/operations.md) — `sp`, file ownership, security
- [development.md](docs/development.md) — layout, loading, comment policy, gotchas
- [testing.md](docs/testing.md) — how spice is tested, and the rules for adding to it

## Layout

```
spice/
├── server.rb          entry point
├── settings.rb        prints what heighliner calls things, for sp and pa
├── server/            config, request, command, session, health, listener
├── wire/              frame format and channel, shared by both halves
├── client/
│   ├── heighliner     the stand-in CLI, lands on the sandbox PATH
│   ├── kaiser         the old name, for scripts and habits that still use it
│   └── spice_client/  client, endpoint, request, terminal, session
├── skills/heighliner/ pi skill, published to sandboxes alongside the client
├── spec/              needs neither docker nor a heighliner install
└── docs/
```

## Tests

```sh
cd spice
bundle install
bundle exec rspec
bundle exec rubocop
```

Neither needs docker nor a heighliner install. If you are adding a spec, read
[docs/testing.md](docs/testing.md) first.

`../crun.d/sp` starts and stops the server; `../crun.d/pa` connects sandboxes to
it.

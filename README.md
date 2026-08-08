# Spice

Heighliner for agents that have no docker.

A `pa` sandbox ([pi-sandbox](https://github.com/davidsiaw/pi-sandbox)) is a
container with no docker socket, so an agent working in it cannot run
`heighliner up` and therefore cannot test the app it is editing. Spice is a
second container that *does* have the socket. The sandbox runs a stand-in
`heighliner` that ships argv over a socket; spice runs the real one and proxies
its terminal back.

```
[pa sandbox]                          [spice container]
  heighliner up                         heighliner up
  spice/client/heighliner  <=socket=>   spice/server.rb
  (stdlib ruby, no docker)              (+ /var/run/docker.sock, + a pty)
```

The connection is duplex: stdout and the exit code come back, stdin and window
resizes go forward. That is what makes `attach`, `login` and `root` work — they
need a terminal in both directions, which a single HTTP request cannot express.

Two ports: `7529` serves `/health` over HTTP, `7530` is the stream.

It is a *command* proxy, not a docker proxy. `docker ps` in the sandbox still
does not work, and never will.

## Everyone must agree on paths

This is the one thing that will bite you. `pa` mounts your project at its real
host path, and heighliner tells the docker daemon to bind-mount that same path.
So spice must also see it at that path — hence `-v "$HOME:$HOME" -e HOME=$HOME`
in `sp up`. If the sandbox says `/home/you/proj` and spice has nothing there,
you get an error saying exactly that.

Because paths already line up, spice does *not* need heighliner's
`_HEIGHLINER_POS=docker` / `_HEIGHLINER_USER_HOME` path-translation vars.

## Use

The image is built and pushed separately, like the heighliner image itself:

```sh
docker build -t davidsiaw/heighliner-spice spice/
docker push davidsiaw/heighliner-spice
```

`sp` only runs it (and pulls it if it is missing):

```sh
sp up                # start the server
sp status            # is it alive
sp env               # the docker flags a sandbox needs
sp down
```

`pa` wires all of that up by itself when a spice server is running, so inside a
sandbox `heighliner up` simply works. `sp env` prints the same flags for
anything else you want to connect.

Being on `heighliner_net` has a second payoff: the sandbox can reach the app it
just booted, by name, via heighliner's own dnsmasq.

## The wire protocol

A line of JSON, then frames of `[type:uint8][length:uint32be][payload]`.

```
header   {token, argv, cwd, env, tty, rows, cols}\n

client -> server   0 stdin   1 stdin-eof   3 resize "<rows> <cols>"
server -> client   0 stdout  2 exit "<code>"  4 error "<message>"
```

The `tty` flag matters: when the client is not a terminal (a pi agent capturing
output) the server puts the pty in raw mode, so output is not littered with
`^M` and piped stdin is not echoed back.

There is no subcommand allowlist. Every heighliner subcommand works, including
the interactive ones. The token is the security boundary, not the command list.

## What it will not do

- **Raw `docker`.** `docker ps` in the sandbox still does not work.
- **Multiple concurrent commands on one connection.** One connection, one
  command.

## Security

Spice runs docker commands on behalf of anything that can open its socket.
Treat it as such.

- Requires a shared `SPICE_TOKEN`. `sp` generates one into
  `~/.local/share/spice/token` (override with `SPICE_TOKEN_FILE`) — *not* under
  `~/.heighliner`, which is typically root-owned because the heighliner docker
  alias writes it as root.
- argv is passed to the child as an argv array, never through a shell.
- Client-supplied env is dropped except for an explicit allowlist.
- No ports are published to the host. Sandboxes reach spice by container name on
  its docker network, so publishing would be attack surface earning nothing.
  `sp status` asks from inside the container via `docker exec`.
- Keep it on a local docker network. Do not put it on a real one.

## Tests

```sh
ruby spice/test/protocol_test.rb
```

Runs a server against a fake heighliner and checks the things that are easy to
get wrong: exit codes, stdin, window size, resize mid-run, `^C` reaching the
remote process group, and every failure message.

## Things to know

- The server runs as the invoking user (`--user`, plus `--group-add` for the
  docker socket's group). It has to: it bind-mounts `$HOME` and shells out to
  docker, buildx and git, and as root those would leave root-owned files in
  `~/.docker` and `~/.heighliner` that break the same tools run on the host.
  The plain `davidsiaw/heighliner` docker alias does write those directories as
  root, so if you use it too they can end up unwritable by you; `sp up` checks
  for that and tells you to chown them rather than failing later inside an
  agent.
- Heighliner state lives on the server. Two sandboxes on one project share one
  `~/.heighliner/config.yml`, which is what you want, but they can also stomp on
  each other's containers.

## Layout

| Path | What |
|---|---|
| `Dockerfile` | `davidsiaw/heighliner` + webrick + the server |
| `server.rb` | entry point: starts the health endpoint and the accept loop |
| `server/config.rb` | everything read from the environment |
| `server/errors.rb` | `Denied` — the one error a client is told about |
| `server/frame.rb` | the wire format, mirrored in the client |
| `server/request.rb` | the opening header: auth, argv, cwd, env, terminal |
| `server/command.rb` | one heighliner run on a pty |
| `server/session.rb` | one connection: socket to pty and back |
| `server/health.rb` | the HTTP health endpoint |
| `server/listener.rb` | accept loop |
| `client/heighliner` | the stand-in CLI: entry point, lands on the sandbox `PATH` |
| `client/spice_client/errors.rb` | `Failure` — the one error the user must act on |
| `client/spice_client/frame.rb` | the wire format, mirrored from the server |
| `client/spice_client/terminal.rb` | this end's terminal, or the absence of one |
| `client/spice_client/endpoint.rb` | where the server is, and connecting to it |
| `client/spice_client/request.rb` | the opening header |
| `client/spice_client/session.rb` | the connection, once it is open |
| `skills/heighliner/` | pi skill telling the agent heighliner exists and the missing docker socket is deliberate |
| `test/protocol_test.rb` | end-to-end protocol test, no docker needed |
| `../crun.d/sp` | start/stop/inspect the server (vendored crun.d, gitignored here) |
| `../crun.d/pa` | wires a sandbox to spice, but only when spice is running |

## How the client reaches the sandbox

The client and its skill are **copied into the server image**. `sp up` then runs
that image once with a docker volume mounted, and copies them out into it. `pa`
mounts the volume at `/opt/spice:ro`, puts it on `PATH`, and passes
`--skill /opt/spice/skills`:

```
/opt/spice/heighliner       the executable, found on PATH
/opt/spice/spice_client/    its library
/opt/spice/skills/          the pi skill
```

The executable has to sit at the volume root, because that root is what goes on
`PATH`.

The skill rides in the same volume for the same reason the client does. Without
it an agent lands in a sandbox with no `docker`, no `/var/run/docker.sock` and
an unexplained `heighliner` binary, and spends several turns working out whether
that is a bug. The skill says up front: it is deliberate, here is how to use it.

The point is not tidiness: it means the client can never be an older version
than the server it talks to. There is no host copy to go stale, and `sp` does
not need to know where your heighliner checkout is.

The token is the one thing that must stay a host file — `pa` has to read it to
pass `SPICE_TOKEN`, and it cannot read a volume.

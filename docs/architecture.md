# Architecture

## The problem

A `pa` sandbox ([pi-sandbox](https://github.com/davidsiaw/pi-sandbox)) has no
docker socket, deliberately. An agent working in one can edit a Heighliner app
but cannot run it, so it cannot test what it just changed.

Spice is a second container that does hold the socket. The sandbox gets a
stand-in `heighliner` that forwards argv; spice runs the real one and proxies
its terminal back.

```
[pa sandbox]                          [spice container]
  heighliner up                         heighliner up
  client/heighliner    <=socket=>       server.rb
  (stdlib ruby, no docker)              (+ /var/run/docker.sock, + a pty)
```

It is a *command* proxy, not a docker proxy. `docker ps` in the sandbox does not
work and is not meant to.

## Everyone must agree on paths

This is the constraint the whole design rests on.

`pa` mounts your project at its real host path. Heighliner then tells the docker
daemon to bind-mount that same path. The daemon resolves it on the host. So
three parties must agree on what `/home/you/proj` means: the sandbox, spice, and
the daemon.

That is why `sp up` passes `-v "$HOME:$HOME" -e HOME=$HOME`, and why the client
sends its `cwd` rather than the server assuming one. If spice cannot see that
directory it refuses immediately with a message saying so, because every later
symptom would be more confusing than the cause.

A useful consequence: since paths already line up, spice does not need
heighliner's `_HEIGHLINER_POS=docker` / `_HEIGHLINER_USER_HOME` path-translation
variables.

## Why a socket and not HTTP

The first version was HTTP with a chunked response. It worked for `up`, `logs`
and the `db_*` commands, and could never work for `attach`, `login` or `root`:

- `Net::HTTP` writes the entire request before reading any response, so there is
  no full-duplex path through it. Without stdin travelling forward, `attach`
  hangs forever with no way to interrupt it.
- Window size changes need a channel of their own.

A raw socket with a small framing layer gives both, in about the same amount of
code, and removes the need for two transports. See [protocol.md](protocol.md).

## How the client reaches the sandbox

The client and the pi skill are copied **into the server image**. `sp up` runs
that image once with a docker volume mounted and copies them out:

```
/opt/spice/client/heighliner     the executable
/opt/spice/client/spice_client/  client-only code
/opt/spice/wire/                 the frame format, shared with the server
/opt/spice/skills/               the pi skill
```

`pa` mounts that volume at `/opt/spice:ro`, puts `/opt/spice/client` on `PATH`,
and passes `--skill /opt/spice/skills`.

The layout mirrors the repo so the client's `../wire` resolves the same whether
it is running from a checkout or from the volume.

The point is not tidiness. Publishing out of the image means the client can
never be an older version than the server it talks to, there is no host copy to
go stale, and `sp` does not need to know where your heighliner checkout is.

The skill rides along for a related reason. Without it, an agent lands in a
sandbox with no `docker`, no `/var/run/docker.sock` and an unexplained
`heighliner` binary, and spends several turns working out whether that is a bug.

## Networking

Everything sits on `heighliner_net`, the network heighliner creates for itself.
That means the sandbox can reach the app it just booted, by name, through
heighliner's own dnsmasq — which is the entire point of letting an agent run the
app at all.

No ports are published to the host. Sandboxes reach spice by container name, so
publishing would be attack surface earning nothing. `sp status` asks from inside
the container with `docker exec`.

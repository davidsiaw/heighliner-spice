# Running spice

## Build and publish

The image is built and pushed separately, like the heighliner image itself:

```sh
docker build -t davidsiaw/heighliner-spice spice/
docker push davidsiaw/heighliner-spice
```

`sp` only runs it, and pulls it if it is missing. Rebuild whenever anything
under `spice/` changes: the client, the shared `wire/` code and the skill are
all published out of the image, so a stale image means a stale client.

Before building, from `spice/`:

```sh
bundle exec rspec
bundle exec rubocop
```

## sp

```sh
sp up        # start the server, publish the client and skill into a volume
sp down      # stop it
sp status    # is it alive
sp logs      # follow its output
sp env       # the docker flags a sandbox needs to reach it
```

`pa` wires all of that up by itself when a spice server is running, so inside a
sandbox `heighliner up` simply works. `sp env` prints the same flags for
anything else you want to connect.

| Variable | Default | Meaning |
|---|---|---|
| `SPICE_IMAGE` | `davidsiaw/heighliner-spice:latest` | image to run |
| `SPICE_NAME` | `heighliner-spice` | container name, and the hostname sandboxes use |
| `SPICE_NETWORK` | `heighliner_net` | docker network |
| `SPICE_PORT` | `7529` | HTTP health |
| `SPICE_STREAM_PORT` | `7530` | the command stream |
| `SPICE_TOKEN_FILE` | `~/.local/share/spice/token` | shared secret |
| `SPICE_CLIENT_VOLUME` | `spice-client` | volume the client is published into |

## File ownership

Spice runs heighliner as the invoking user (`--user`, plus `--group-add` for the
docker socket's group). It has to: it bind-mounts `$HOME` and shells out to
docker, buildx and git. As root, those leave root-owned files in `~/.docker` and
`~/.heighliner` that then break the same tools run directly on the host.

The plain `davidsiaw/heighliner` docker alias *does* write those directories as
root, so if you use it too they can end up unwritable by you. `sp up` checks for
this and refuses to start, because the alternative is failing later inside an
agent that cannot see host paths at all and will misread it as its own problem:

```sh
sudo chown -R "$(id -u):$(id -g)" ~/.heighliner ~/.docker
```

The token deliberately lives in `~/.local/share/spice/`, outside
`~/.heighliner`, for the same reason.

## Shared state

Heighliner state lives on the server. Two sandboxes working on one project share
one `~/.heighliner/config.yml`, which is what you want, but they can also stomp
on each other's containers.

## Security

Spice runs docker commands on behalf of anything that can open its socket.
Treat it accordingly.

- A shared `SPICE_TOKEN` is required, compared in constant time. `sp` generates
  one with mode `600`.
- argv reaches the child as an argv array, never through a shell. The spawn is
  `sh -c 'cd "$0" && exec heighliner "$@"' cwd argv...`, so `$0` and `$@` carry
  the client's strings as separate words and nothing in them is ever parsed.
- Client-supplied env is dropped except for an explicit allowlist.
- No ports are published to the host.
- Keep it on a local docker network. Do not put it on a real one.

There is no subcommand allowlist. Every heighliner subcommand works, including
the interactive ones. The token is the boundary, not the command list.

## What a sandbox may not do

Four commands are refused, in `server/policy.rb`. This is about blast radius and
ownership, not security.

| Command | Why |
|---|---|
| `init` | names the environment and allocates its ports, once, for everyone on the project |
| `deinit` | throws that away again |
| `shutdown` | stops the shared proxy, DNS and browser containers every project depends on |
| `set` | rewrites the domain suffix and certificate source for every project on the server |

An agent that runs any of these to make its own build work changes something
outside the project it was asked to work on, silently.

Each refusal names the command, says why in one sentence, and gives something to
do next -- what to ask for, or the narrower command that usually solves it. The
phrasing is deliberately "one for the user rather than spice": an agent that
reads a refusal as a wall starts hunting for a workaround, and a workaround here
means editing the `Steerfile` or the app to compensate for a setting it could
not change.

Reading is untouched. `show http-suffix` and `show cert-source` both work, and
the skill points agents at them.

Add another only if it has the same shape: host-wide or setup-level effect, no
per-project meaning, and a person who owns the decision. `down` and `up` stay
available precisely because they are the project-scoped version of `shutdown`.

# Running spice

## Build and publish

The image is built and pushed separately, like the heighliner image itself:

```sh
docker build -t davidsiaw/heighliner-spice spice/
docker push davidsiaw/heighliner-spice
```

`sp up` only runs it, and pulls it if it is missing; `sp update` pulls and
restarts. Rebuild whenever anything under `spice/` changes: the client, the
shared `wire/` code and the skill are all published out of the image, so a stale
image means a stale client.

After pushing a new image, `sp update` on each host is the whole upgrade.

Before building, from `spice/`:

```sh
bundle exec rspec
bundle exec rubocop
```

## sp

```sh
sp up        # start the server, publish the client and skill into a volume
sp update    # pull a newer image and restart onto it
sp down      # stop it
sp status    # is it alive
sp logs      # follow its output
sp env       # the docker flags a sandbox needs to reach it
```

`up` pulls only when the image is missing. Starting the server is the common
operation and it should not need the network, or a registry having a bad day.

`update` is how you upgrade, and it always restarts afterwards — even when the
pull changed nothing. Both halves come out of this one image, so a pull on its own
would leave the running server on the old image and the client volume on the new
one, which is the drift the shared image exists to make impossible.

`pa` wires all of that up by itself when a spice server is running, so inside a
sandbox `heighliner up` simply works. `sp env` prints the same flags for
anything else you want to connect.

| Variable | Default | Meaning |
|---|---|---|
| `SPICE_IMAGE` | `davidsiaw/heighliner-spice:latest` | image to run |
| `SPICE_NAME` | `heighliner-spice` | container name, and the hostname sandboxes use |
| `SPICE_NETWORK` | whatever heighliner's config names | docker network. Read from heighliner rather than assumed, because a pre-rename install calls it `kaiser_net` — see [settings.md](settings.md) |
| `SPICE_PORT` | `7529` | HTTP health |
| `SPICE_STREAM_PORT` | `7530` | the command stream |
| `SPICE_TOKEN_FILE` | `~/.local/share/spice/token` | shared secret |
| `SPICE_CLIENT_VOLUME` | `spice-client` | volume the client is published into |
| `SPICE_DOCKER_CONFIG` | `~/.local/share/spice/docker` | the server's own docker CLI config dir, written by `sp up` (see [Reaching the docker daemon](#reaching-the-docker-daemon)) |

## Reaching the docker daemon

Two things must be right, and both were wrong on macOS until they were found by
running `kaiser show http-suffix` against a real project:

**`DOCKER_HOST` is set explicitly.** Spice mounts `$HOME` at its real path, so the
docker CLI inside the container reads *your* `~/.docker/config.json`, finds
`"currentContext": "desktop-linux"`, and dials that context's endpoint —
`unix:///Users/you/.docker/run/docker.sock`, a host path that does not exist in
the container. The socket correctly mounted at `/var/run/docker.sock` was ignored,
and every docker-touching command failed with *"Cannot connect to the Docker
daemon"*. CLI precedence is `DOCKER_HOST` > context > default, so `sp` names the
socket explicitly.

**The socket's group is added, and it is measured from inside a container.**
`sp` runs one `alpine stat -c '%g' /var/run/docker.sock` with the socket mounted,
and passes the result to `--group-add`.

Asking the host instead was wrong twice, and both mistakes produced the identical
*"permission denied while trying to connect to the docker API"*:

1. `stat -c` is GNU syntax and macOS ships BSD `stat`, which needs `-f`. The call
   failed silently — stderr inside `$( )`, with a fallback swallowing it — so
   `${DOCKER_GID:+--group-add ...}` expanded to nothing and no group was added.
2. Fixing the syntax was still not enough, because `/var/run/docker.sock` on macOS
   is a **symlink** into Docker Desktop's VM and `stat` does not follow symlinks by
   default. Measured on one host:

   | asked | answer |
   |---|---|
   | host, `stat -f '%u %g %Sp'` | `0 1 lrwxr-xr-x` — the *link*, gid 1 |
   | inside a container, `stat -c '%u %g %a'` | `0 0 660` — the *socket* |

   So the BSD form yielded `--group-add 1`: a real group, and the wrong one.
   `docker inspect ... {{.HostConfig.GroupAdd}}` confirmed `[1]`.

The container probe has no GNU/BSD branch and no symlink ambiguity, because it
asks in the namespace where the number is actually used. It costs one short
container run per `sp up`, and if it fails the flag is omitted rather than passed
a bogus value.

Why group `0` is sufficient: the socket is `root:root` mode `0660`, and the server
runs `--user 501:20`. The uid does not match the owner, so the owner bits do not
apply — but a supplementary group of `0` matches the socket's gid, so the group
`rw` bits do.

**The server gets its own docker CLI config.** Third instance of the same root
cause: `$HOME` is mounted, so the CLI reads your `~/.docker/config.json`, which on
a Mac says `"credsStore": "desktop"`. It then tries to exec
`docker-credential-desktop` — a macOS binary absent from a Linux container — and
**every image pull fails**, including public ones that need no credentials:

```
error getting credentials - err: exec: "docker-credential-desktop":
executable file not found in $PATH
```

`sp up` writes `~/.local/share/spice/docker/config.json`, keeping the keys that
travel (`auths` entries that actually carry a token) and dropping the ones that
name host-only executables (`credsStore`, `credHelpers`) or a host-only endpoint
(`currentContext`). The server runs with `DOCKER_CONFIG` pointed at it.

Do **not** fix this by editing `~/.docker/config.json`. Removing `credsStore`
works, and it does so by moving every registry credential you own out of the macOS
Keychain into base64 in a plaintext file — a real security downgrade to work
around a path problem. Your host config is right for your host; the container
needs a different one, so it gets a different one.

An empty `{}` is written when the host has no config, when it cannot be parsed, or
when nothing in it is worth carrying. That is the correct state for anonymous
pulls of public images.

A supplementary group is safe here: a new file takes the process's **primary**
gid, which `--user` still pins to yours, so `--group-add` cannot reintroduce the
root-owned-files problem described next.

## File ownership

Spice runs heighliner as the invoking user (`--user`, plus `--group-add` for the
docker socket's group). It has to: it bind-mounts `$HOME` and shells out to
docker, buildx and git. As root, those leave root-owned files in `~/.docker` and
heighliner's config dir that then break the same tools run directly on the host.

The plain `davidsiaw/heighliner` docker alias *does* write those directories as
root, so if you use it too they can end up unwritable by you. `sp up` checks for
this and refuses to start, because the alternative is failing later inside an
agent that cannot see host paths at all and will misread it as its own problem:

```sh
sudo chown -R "$(id -u):$(id -g)" ~/.heighliner ~/.docker
```

`sp` names the directory it actually checked, which on a pre-rename install is
`~/.kaiser`.

The token deliberately lives in `~/.local/share/spice/`, outside the config dir,
for the same reason.

## Shared state

Heighliner state lives on the server. Two sandboxes working on one project share
one `config.yml`, which is what you want, but they can also stomp
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

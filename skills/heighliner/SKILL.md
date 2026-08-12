---
name: heighliner
description: Boot, run and test a Heighliner web app from this sandbox - any project containing a Steerfile, Heighliner.config or heighliner.config. Use when asked to run the app, start or restart the server, check that the app works, hit an endpoint, run migrations or a test suite inside the app container, reset or seed the database, or read app logs. This sandbox has no docker socket on purpose; the heighliner command is proxied to a spice server that has one, so docker not being installed is expected and is not the problem.
---

# Heighliner in this sandbox

This project is run by Heighliner: a `Steerfile` describes one app container and
at most one database container, and `heighliner` starts them.

**There is no docker socket here, by design.** `/var/run/docker.sock` does not
exist and `docker` is not installed. Do not try to install it and do not treat
its absence as the fault. `heighliner` at `/opt/spice/heighliner` forwards every
command to a spice server that holds the socket, runs the real heighliner there,
and streams the result back. Use it exactly like the real CLI.

## Check it works first

```sh
heighliner show http-suffix
```

That exercises the whole path - network, auth, the project directory being
visible to the server, Steerfile parsing - and prints the domain suffix you will
need below. If it fails, the message says what to do; the common ones are in
[references/troubleshooting.md](references/troubleshooting.md). Do not debug
further until this succeeds.

Note that bare `heighliner show` is *supposed* to fail: it lists what can be
shown and exits non-zero. Always give it an argument.

## If this project still says kaiser

Heighliner used to be called kaiser, and the rename left nothing for you to do:

- `kaiser` is on the PATH here and runs the same binary, so an old script or
  README that calls it still works.
- A `Kaiserfile` is read as-is. The accepted names are `Kaiserfile`, `Steerfile`,
  `Heighliner.config` and `heighliner.config`; the contents are identical.
- Config lives in `~/.kaiser` on an old install, and heighliner keeps using it.

So **do not rename a `Kaiserfile`**, and do not add a `Steerfile` beside one. It
already works, and doing either would change the project for everyone on it. If
both files exist, `Steerfile` is the one that wins.

## The core loop

```sh
heighliner init <envname>   # once per project; fails harmlessly if already done
heighliner up               # build the image and start app (+ db)
```

`up` is slow the first time: it is a full docker build. It waits for the app to
answer HTTP and fails loudly if the container dies, so a successful exit really
does mean the app is serving.

Then reach the app by hostname. The host is `<envname>.<suffix>`, and **the
suffix is configurable - do not assume `lvh.me`**:

```sh
suffix=$(heighliner show http-suffix)
curl -sS "http://<envname>.$suffix"
```

If the user has HTTPS certificates set up for that suffix, `https://` works too;
try `http://` first.

This resolves because the sandbox shares Heighliner's docker network and DNS.
Prefer it over guessing ports - `-p` bindings are on the host, not here.

To find `<envname>` when you did not choose it yourself, run `heighliner init x`
in the project: if it is already initialised it refuses and names the existing
environment. Nothing is changed by the attempt.

## Running commands inside the app container

```sh
heighliner login bin/rails db:migrate
heighliner login bundle exec rspec
heighliner root apk add --no-cache curl     # as root
```

These work, including interactive ones. But you are not attached to a terminal,
so **never run a command that waits for input** - no `rails console`, no `sh`,
no editors, no prompting installers. Pass the whole command up front.

## When something is wrong

```sh
heighliner logs             # app container output - always look here first
heighliner up               # rebuild and restart, keeping the database
```

Editing application source does not need a rebuild if the Steerfile bind-mounts
it; editing the `Dockerfile` or `Steerfile` does.

**`heighliner down` is destructive to development data by design.** To restart,
use `heighliner up` on its own - it does not need a `down` first.

If you do need `down`, treat `down` then `up` then `db_reset` as a single unit
of work, and do not stop part-way. Before any `down` whose data you care about,
take a named snapshot:

```sh
heighliner db_save before-migration-experiment
```

Named snapshots restore reliably, so that one command is what turns a risky step
into a reversible one. Ask before discarding data you did not create.

## Database

```sh
heighliner db_reset         # restore the saved default state
heighliner db_save <name>   # snapshot current state
heighliner db_load <name>   # restore a snapshot
```

Snapshots are per git branch. See
[references/workflows.md](references/workflows.md) for environments, services
and branch behaviour.

## Four commands belong to the user

`init`, `deinit`, `shutdown` and `set` are refused, and spice will tell you so
with a short explanation and what to ask for. They are either a setup decision
or they affect every project sharing the server, so a person makes the call.

This is a small list on purpose. Everything that matters day to day is yours:
`up`, `down`, `attach`, `logs`, `login`, `root`, every `db_*` command, and all
of `show`.

When you hit one, the useful move is the same each time: **say plainly what you
were trying to do and what you need**, then continue with the rest of the work.
A one-line request the user can act on is worth far more than a workaround.

- Not initialised yet? Ask for `heighliner init <name>` on the host, then carry
  straight on.
- Think the shared containers are wedged? Try `heighliner down` then
  `heighliner up` first; that fixes it most of the time.
- Suffix or certificates look wrong? `heighliner show http-suffix` and
  `heighliner show cert-source` are yours to read - report what they say.

Being right that a setting is wrong does not make it yours to change, and
nobody expects you to work around it.

## Rules

- Report what `heighliner` actually printed. Its errors are specific; do not
  paraphrase them into "it didn't work".
- Do not edit the `Steerfile` to work around a failure without saying so - it is
  shared configuration that every developer on the project gets.
- If the spice server is down, that is a host-side fix the user must make
  (`sp up`). Say so and stop rather than looking for another way to run docker.

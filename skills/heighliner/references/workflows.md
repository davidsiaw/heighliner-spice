# Workflows

## Environments

`heighliner init <name>` binds the current directory to an environment name and
allocates it host ports. The name becomes the hostname: environment `myapp` is
served at `http://myapp.<suffix>`, where the suffix comes from
`heighliner show http-suffix`. It defaults to `lvh.me` but is frequently changed
- always ask rather than assuming.

One directory, one environment. `heighliner init` in an already-initialised
directory fails and tells you the existing name; that is how you look it up.
`heighliner deinit` releases it.

## Branches

Built images are tagged `heighliner:<env>-<git branch>`, and saved database
states live under `<env>/<branch>/`. Switching branches and running
`heighliner up` gives you a separate image and separate database state, with no
extra work. It also means the first `up` after switching branches is a full
rebuild.

## Database state

```sh
heighliner db_save <name>       # snapshot
heighliner db_load <name>       # restore
heighliner db_reset             # back to the "default" snapshot
heighliner db_reset_hard        # delete the volume and re-provision
```

`default` is created automatically the first time `heighliner up` provisions the
database, by running the Steerfile's `db_reset_command`. `db_reset` is the fast
way back to a clean fixture set between test runs; `db_reset_hard` is the slow
way when the database itself is corrupt.

A path starting with `./` writes into the current directory instead of the
config directory, e.g. `heighliner db_save ./fixture.tar.bz`.

## Services

A `Steerfile` may declare extra containers:

```ruby
service :redis, image: "redis:7"
```

They start and stop with the app. They are reachable from the app container by
the name `<env>-<service>`, not by `localhost`.

## Reaching things

Everything shares one docker network, and this sandbox is on it:

- The app through the proxy: `http://<env>.<suffix>`
  (`suffix=$(heighliner show http-suffix)`)
- The app container directly: `http://<env>-app:<exposed port>` - this bypasses
  the proxy and DNS entirely, so it is the better check when you are trying to
  work out *whether* the proxy is the problem
- The database: `<env>-db` on the port the `Steerfile` declares
- A service: `<env>-<service>`

Host port mappings are irrelevant here - those exist for the user's browser, not
for this sandbox.

## The Steerfile

It is Ruby, evaluated at load. The parts you will meet:

| Directive | Meaning |
|---|---|
| `dockerfile "path"` | which Dockerfile to build |
| `expose "3000"` | the port the app listens on inside the container |
| `db image, port:, data_dir:, ...` | the database container |
| `app_params "-e FOO=bar"` | extra docker flags for the app container |
| `db_reset_command "..."` | how to build the default database state |
| `attach_mount "from", "to"` | bind mounts added by `attach` |
| `type :http` | makes `up` wait for a 200 before returning |

## Inspecting configuration

```sh
heighliner show http-suffix    # domain suffix, e.g. lvh.me or something custom
heighliner show ports          # host ports for app and db (not usable from here)
heighliner show cert-source    # where HTTPS certificates come from
```

Bare `heighliner show` lists these and exits non-zero; that is not a failure.

Strings are ERB-evaluated, so `<%= db_container_name %>` works inside
`app_params` - that is how the app is given its `DATABASE_URL`.

Treat this file as shared project configuration. Changing it changes it for
everyone, so say what you changed and why.

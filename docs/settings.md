# Settings, and why the host scripts do not know them

`sp` and `pa` have to name three things before they can run any container: which
directory heighliner keeps its config in, which docker network to join, and which
container is heighliner's resolver.

None of those names belong to spice. They are heighliner's, they live in
heighliner's `config.yml`, and heighliner may change them. So they are asked for
rather than hardcoded:

```sh
eval "$(_spice)"
echo "$SPICE_HL_NETWORK"   # heighliner_net, or kaiser_net
```

`_spice` runs `ruby /app/spice/settings.rb` in the spice image, where the
heighliner gem is installed. Same division of labour as the rest of `crun.d`:
`rb` and `be` are three lines because `cmdgen.rb` does the thinking.

## The kaiser problem

Heighliner used to be called [kaiser](https://github.com/degica/kaiser). The
commands and the config format never changed, and heighliner keeps using
`~/.kaiser` when that directory exists and `~/.heighliner` does not — so an old
install carries on working without migration.

But a `config.yml` written by kaiser says:

```yaml
:networkname: kaiser_net
:shared_names:
  :dns: kaiser-dns
```

A script that hardcodes `heighliner_net` therefore starts spice on a network the
proxy is not on, and points `--dns` at a container that does not exist. Nothing
errors. `sp up` succeeds, `pa` starts, `heighliner up` succeeds — and the app the
agent just booted is unreachable, with no message anywhere saying why.

That is the failure this exists to prevent, and it is why the answer comes from
one place.

## Who reads what

| Reader | How | Why |
|---|---|---|
| `sp up`, `sp status`, `sp env` | `eval "$(_spice)"` | it is about to start a container anyway |
| `pa` | `docker inspect` labels on the server container | it must stay fast, and the answer already exists |

`sp up` stamps what it resolved onto the server container as
`spice.heighliner.*` labels. `pa` reads them from the `docker inspect` it already
makes to check whether spice is running, so launching a sandbox costs no extra
container start. A server that predates the labels answers empty, and `pa` falls
back to the heighliner defaults — correct by construction, since that is the only
network such a server could have joined.

## Adding a setting

1. a method on `HeighlinerSettings`, with a default
2. an entry in `Settings::VARIABLES`
3. a label in `sp`'s `hl_labels` if `pa` needs it

`HeighlinerSettings` asks `Heighliner::Config.detect_config_dir` when the
installed gem is new enough to have it, and otherwise applies the same rule
itself. Both paths are tested. Keep it that way: the gem is the authority, and
the fallback exists only so an older image still answers.

Values are printed single-quoted, because a config file is data and must never
become shell syntax.

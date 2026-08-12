# Troubleshooting

Read the message `heighliner` printed. Each of these is a distinct cause with a
distinct fix; they are not interchangeable.

## "SPICE_URL is not set"

This sandbox was started without a spice server running, so nothing was wired
up. Nothing you can do from in here. Tell the user to run `sp up` on the host
and restart the sandbox.

## "cannot reach the spice server"

The server was running when this sandbox started but is not answering now,
or DNS cannot resolve it. Host-side: `sp status`, then `sp up`. Again, not
fixable from in here.

## "cwd ... does not exist on the spice server"

The spice server cannot see this directory at the same absolute path. It mounts
the user's home directory; a project outside it is invisible to the server.
Report the path and stop - this is a host-side mount problem.

## "bad or missing token"

The sandbox's `SPICE_TOKEN` does not match the server's, which normally means
the server was restarted with a fresh token after this sandbox started. Restart
the sandbox.

## Permission denied, or a missing file, under a path you cannot see

For example `Permission denied @ rb_sysopen - /home/someone/.heighliner/dnsconf`,
often as a raw Ruby backtrace.

That path is on the **spice server**, not here. This sandbox only has the
project directory mounted, so a home directory shown in such an error does not
exist here at all - `ls` on it correctly says "No such file or directory", and
that is not a second bug.

You cannot fix this. Do not try to create the directory, do not chown anything,
do not look for the docker socket. Report the exact error and tell the user to
run, on the host:

```sh
sudo chown -R "$(id -u):$(id -g)" ~/.heighliner ~/.docker
```

If the path in the error is `~/.kaiser`, name that instead: heighliner used to be
called kaiser and keeps using the old directory when it is the only one there.

The general rule: **an absolute path in an error that does not exist here is the
server's filesystem.** Treat it as a host-side problem and stop.

## "`heighliner <command>` is one for the user rather than spice"

Deliberate, not a bug, and the message says what to ask for. It covers `init`,
`deinit`, `shutdown` and `set`.

Pass the request on in one line and keep going with whatever else you can do.
Being confident the change is correct does not make it yours to make.

## "No Steerfile in current directory"

Every command fails this way, including `show`. The message lists the names
heighliner accepts: `Kaiserfile`, `Steerfile`, `Heighliner.config`,
`heighliner.config`. Read the list it printed rather than assuming.

A `Kaiserfile` is **not** the cause -- it is accepted (it is the pre-rename name
for the same file). If you see this error, you are in the wrong directory: the
project root is wherever that file is. `ls` and check before concluding anything
about the project's setup, and do not create a `Steerfile` to "fix" it.

## "No environment? Please use heighliner init <name>"

The project has not been set up on this server yet, and `init` is the user's to
run. Ask for `heighliner init <name>` on the host - suggest a name based on the
project directory - and continue once it exists.

## The app is served on an unexpected domain

Check rather than assume: `heighliner show http-suffix`. The suffix defaults to
`lvh.me` but is frequently changed. If it genuinely looks wrong, report the
value you saw and what you expected; changing it is the user's to do.

## HTTPS fails, or certificates are missing

`heighliner show cert-source` says where certificates come from. Fixing it means
`heighliner set`, which is the user's. Report what you found.

Try `http://` before concluding anything is broken; most setups do not have
certificates configured at all.

## The database is empty, or fixtures have vanished

Most likely something ran `heighliner down`, which discards development data by
design. `heighliner db_reset` restores the `default` snapshot; a named snapshot
restores with `heighliner db_load <name>`.

Avoid it next time: `heighliner up` restarts without a `down`, and
`heighliner db_save <name>` before a risky step makes it reversible.

## "App container died. Run `heighliner logs` to see why."

This one *is* yours to fix. The image built and started but the process exited.
`heighliner logs` shows why - usually a missing dependency, a bad start command,
or the app not binding to `0.0.0.0`.

An app that only listens on `127.0.0.1` inside its container is unreachable from
outside it. It must bind `0.0.0.0` on the port the `Steerfile` exposes.

## "Failed with HTTP status: 500" (or any non-200)

The container is up and answering, but the app is erroring on `/`. `heighliner
logs` has the stack trace. This is an application bug, not a Heighliner problem.

## The build fails

The output is ordinary `docker build` output; read it as such. Note the build
context is the project directory and the `Dockerfile` is the one named in the
`Steerfile`, which is not necessarily `./Dockerfile`.

## A command hangs

Almost certainly it is waiting for input that will never come. Nothing here is
attached to a terminal. Re-run it non-interactively - add `-y`, pass the
argument up front, or set the env var it is prompting for.

## `docker` is not installed

Expected. See the main skill. Do not install it, and do not look for the socket.

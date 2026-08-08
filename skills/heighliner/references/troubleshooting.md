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

The general rule: **an absolute path in an error that does not exist here is the
server's filesystem.** Treat it as a host-side problem and stop.

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

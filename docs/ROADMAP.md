# Roadmap

This file records accepted directions. Nothing here is current runtime
authority; if it is not implemented and tested, it does not constrain anything.

## Under consideration

### More package adapters

APT is the only implemented adapter. The configuration model already separates
"which packages" from "how to install them," so `dnf` and `pacman` adapters are
tractable. Neither exists. Anyone adding one needs the same locale-independent
candidate detection the APT path has, plus test coverage.

### More effect verbs

Contract schema 1 supports three effects — `FILE_NO_WRITE`,
`AUTHORIZATION_LANE_NO_CHANGE`, `COMMAND_RESOLUTION_NO_CHANGE` — and two
detection facts — `ROOT_REGULAR_FILE`, `ROOT_EXECUTABLE`.

Plausible additions: a directory-level no-write, a systemd-unit fact, an
environment-variable no-change. Each new verb needs a runtime check that is
cheap, read-only, and unambiguous, plus a rejection test. A verb that can only
be checked expensively or heuristically does not belong in a contract.

Adding a verb means schema 2 and a migration path for existing contracts. That
cost is why the initial set is small.

### Retiring the schema-1 runtime reader

Version 0.5.x still reads the schema-1 Home session field written by 0.4.x, and
maps it only for the old Home profile. Reinstalling writes schema 2. The
compatibility reader is scheduled for removal in 0.6.0.

## Deferred, with reasons

### `tmuxp`

Deferred until repeatable multi-window layouts are being rebuilt by hand often
enough to justify configuration files. Session navigation deliberately stops at
list, pick, attach, and create.

### Zellij

Not installed or configured. Adding it would introduce a second session
architecture alongside tmux, and the local session command exists precisely to
avoid that.

### Automatic process restoration

Permanently declined under every profile. tmux-resurrect is supported as an
optional Home adapter with `@resurrect-processes 'false'` — layouts and working
directories come back, programs do not. Relaunching a shell that was running a
privileged command, an agent, or a development server is not something a
convenience layer should do on your behalf.

### Host configuration

WSL Plus will not make `/etc/wsl.conf`, `.wslconfig`, `/etc/resolv.conf`, VPN
routes, or firewall rules an implicit installer side effect. If a host
configuration command is ever added, it must be a separate explicit command,
policy-gated, and rollback-capable.

### Repository synchronization

Out of scope, permanently. Cross-filesystem access is not permission for
multiple writers to mutate one checkout.

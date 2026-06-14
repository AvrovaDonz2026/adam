# Adam Architecture

Adam is a POSIX `sh` front-end for pkgsrc.

## Goals

- Provide apt-family ergonomics.
- Prefer pkgsrc source builds by default.
- Keep `pkgin` as an optional binary backend.
- Maintain Adam-managed state in a plain-text database.
- Avoid pbulk in v1.

## Runtime Layers

### CLI dispatcher

The `adam` script parses global options, then dispatches to a command function.

### Config

Configuration comes from built-in defaults, system config, user config, and CLI flags.

### Database

The active database is `adam-pkg.db`.

Adam keeps writable table files under the state directory and writes a combined database snapshot for inspection and portability.

### Resolver

The resolver maps package names to pkgsrc paths by using the available package table generated from the pkgsrc tree.

### Planner

The planner resolves dependency paths and emits a dependency-first build order.

### Executor

The executor runs pkgsrc make targets or, in binary mode, delegates to `pkgin`.
Source downloads use pkgsrc `make fetch`; builds use `make package`; installs use `make install`.

## State Authority

Adam treats `adam-pkg.db` as authoritative for Adam-managed decisions.
The system pkgdb remains the low-level package database used by pkgsrc.

If external package tools change the system state, Adam may report drift through `adam check`.
Use `adam db resync` to import system pkgdb state into Adam.

## Known Boundaries

- Adam does not implement pbulk in v1.
- Some apt commands are nearest equivalents, not Debian semantic clones.
- `purge` cannot reliably remove application-specific configuration files that pkgsrc itself does not track.
- `autoremove` is conservative: it only removes Adam-managed automatic packages that are no longer dependency-reachable from installed manual roots.
- `autoclean` only removes Adam state scratch files. It does not delete pkgsrc distfiles or package archives.

# Adam

[![CI](https://github.com/AvrovaDonz2026/adam/actions/workflows/ci.yml/badge.svg)](https://github.com/AvrovaDonz2026/adam/actions/workflows/ci.yml)
[![pkgsrc Command Surface](https://github.com/AvrovaDonz2026/adam/actions/workflows/pkgsrc-command-surface.yml/badge.svg)](https://github.com/AvrovaDonz2026/adam/actions/workflows/pkgsrc-command-surface.yml)

Adam is a source-first package manager front-end for pkgsrc, written in POSIX `sh`.

It aims to provide an apt-style command surface while using pkgsrc as the primary package source.
Binary package support through `pkgin` is available as an opt-in backend.

## Design

- Default install path: pkgsrc source builds.
- Optional binary path: `--binary`.
- No pbulk in v1.
- English documentation and help text.
- Authoritative state file: `adam-pkg.db`.

## Quick Start

```sh
./adam update
./adam install foo
./adam --binary install foo
./adam search foo
./adam show foo
./adam db dump
```

## Configuration

Adam reads configuration in this order:

1. Built-in defaults
2. `/usr/pkg/etc/adam.conf`
3. `~/.config/adam/config`
4. Environment variables
5. Command-line flags

Example config:

```sh
ADAM_PKGSRCDIR=/usr/pkgsrc
ADAM_LOCALBASE=/usr/pkg
ADAM_STATE_DIR=/usr/pkg/var/db/adam
ADAM_DB_PATH=/usr/pkg/var/db/adam/adam-pkg.db
ADAM_ROOT_CMD=auto
ADAM_MAKE_CMD=bmake
ADAM_PKGIN_CMD=pkgin
```

## Package Database

Adam stores state in a plain-text database named `adam-pkg.db`.

Default location:

```text
/usr/pkg/var/db/adam/adam-pkg.db
```

The database tracks:

- installed packages
- available pkgsrc metadata
- manual/auto/hold marks
- transaction history
- config values
- file records

Adam treats this database as its authoritative state for Adam-managed operations.
The system pkgdb remains the low-level install substrate used by pkgsrc tools.
If Adam and the system pkgdb drift apart, run:

```sh
./adam check
./adam db resync
```

## Commands

Common commands:

- `help`
- `update`
- `install`
- `remove`
- `purge`
- `upgrade`
- `full-upgrade`
- `autoremove`
- `search`
- `show`
- `list`
- `depends`
- `rdepends`
- `policy`
- `mark`
- `build`
- `plan`
- `source`
- `download`
- `build-dep`
- `clean`
- `autoclean`
- `check`
- `doctor`
- `config`
- `db`

## Source-first Model

`adam install PKG` resolves the package in pkgsrc, creates a dependency plan, and runs the pkgsrc install target in dependency order. Requested packages are recorded as manual; dependencies installed by Adam are recorded as automatic so conservative `autoremove` can clean them later when they become orphaned.

Use binary mode explicitly:

```sh
./adam --binary install PKG
```

## Development Workflow

Development uses milestone commits. Each major capability should be staged with `git add` and committed before moving to the next capability.

Suggested milestones:

1. `chore: scaffold adam core`
2. `feat: add adam package database`
3. `feat: implement source-first pkgsrc install`
4. `feat: add apt-family commands`
5. `feat: add optional pkgin backend`
6. `test: add shell test suite`
7. `docs: complete English documentation`

## Testing

Run:

```sh
sh tests/run.sh
```

Run real pkgsrc smoke tests:

```sh
sh tests/pkgsrc-smoke.sh command-surface
sh tests/pkgsrc-smoke.sh lifecycle-only
sh tests/pkgsrc-smoke.sh command-index-full
```

`command-surface` is the fast real-pkgsrc path used on push and pull request.
`lifecycle-only` covers install, remove, and autoremove without re-running the full index.
`command-index-full` keeps the expensive index-refresh path as a manual check.

The fake suite uses fake tools and a fake pkgsrc tree. It covers every public Adam command and failure paths.

CI is split by responsibility:

- `CI`: fake command coverage on Ubuntu, macOS, and BSD.
- `pkgsrc Command Surface`: fast real pkgsrc command coverage on Linux x64 and NetBSD x64.
- `pkgsrc Lifecycle`: representative real install/remove coverage on Linux, macOS, and BSD.
- `pkgsrc Full Lifecycle`: manual/nightly full lifecycle on x64/arm.
- `pkgsrc Index Surface`: manual full-index command coverage.

The real pkgsrc jobs download stable pkgsrc and exercise source-first behavior under the appropriate bootstrap/toolchain for each platform.

## More Documentation

- [Command reference](COMMANDS.md)
- [Configuration](CONFIG.md)
- [Architecture](ARCHITECTURE.md)

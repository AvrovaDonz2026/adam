# Adam Configuration

## Files

Adam reads:

1. Built-in defaults
2. `/usr/pkg/etc/adam.conf`
3. `~/.config/adam/config`
4. CLI flags

## Keys

```sh
ADAM_PKGSRCDIR=/usr/pkgsrc
ADAM_LOCALBASE=/usr/pkg
ADAM_STATE_DIR=/usr/pkg/var/db/adam
ADAM_DB_PATH=/usr/pkg/var/db/adam/adam-pkg.db
ADAM_MAKE_CMD=bmake
ADAM_ROOT_CMD=auto
ADAM_PKGIN_CMD=pkgin
```

## Useful Commands

```sh
adam config dump
adam config get ADAM_PKGSRCDIR
adam db path
adam db dump
adam doctor
```


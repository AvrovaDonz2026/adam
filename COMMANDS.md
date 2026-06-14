# Adam Command Reference

## apt-style commands

### `adam update`
Refresh package index data.

### `adam install PKG...`
Install packages. By default Adam uses pkgsrc source builds.

### `adam --binary install PKG...`
Use the pkgin backend.

### `adam remove PKG...`
Remove packages.

### `adam purge PKG...`
Remove packages and clean Adam-managed metadata.

### `adam upgrade`
Upgrade installed packages.

### `adam full-upgrade`
Upgrade with full dependency resolution.

### `adam autoremove`
Remove automatically installed packages that are no longer needed.

### `adam search PATTERN`
Search package metadata.

### `adam show PKG`
Show package metadata.

### `adam list`
List packages.

### `adam depends PKG`
Show direct dependencies.

### `adam rdepends PKG`
Show reverse dependencies.

### `adam policy PKG`
Show installation policy information.

### `adam mark manual|auto|hold|unhold PKG...`
Change package marks.

### `adam build PKG...`
Build packages from pkgsrc without installing them.

### `adam plan PKG...`
Print the planned dependency build order.

### `adam source PKG...`
Print pkgsrc paths for packages.

### `adam download PKG...`
Download package artifacts when supported.

### `adam build-dep PKG...`
Build package dependencies.

### `adam clean`
Remove local scratch data.

### `adam autoclean`
Clean stale package data.

### `adam check`
Check Adam state against the system package database.

### `adam doctor`
Inspect the local Adam environment.

## Notes

- Adam is source-first by default.
- `pkgin` is optional.
- `adam-pkg.db` is the authoritative Adam-managed state store.


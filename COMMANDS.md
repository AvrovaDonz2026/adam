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
Conservatively remove Adam-managed automatic packages that are no longer reachable from any installed manual package. Held packages are never autoremoved.

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
Change package marks. For installed packages, `manual` and `auto` also update Adam's installed automatic flag.

### `adam mark minimize-manual`
Mark installed manual packages as automatic when they are reachable as dependencies of other manual packages.

### `adam reinstall PKG...`
Reinstall packages using the current backend.

### `adam build PKG...`
Build packages from pkgsrc without installing them.

### `adam plan PKG...`
Print the planned dependency build order.

### `adam source PKG...`
Print pkgsrc paths for packages.

### `adam download PKG...`
Download package artifacts. In source mode Adam runs pkgsrc `make fetch`; in binary mode it delegates to `pkgin download`.

### `adam build-dep PKG...`
Build package dependencies.

### `adam satisfy EXPR...`
Install packages that satisfy dependency expressions.

### `adam indextargets`
List Adam index locations.

### `adam changelog PKG`
Search pkgsrc changelog entries for a package name.

### `adam madison PKG...`
Show source version information for packages.

### `adam audit`
Run pkgsrc audit when `pkg_admin` is available.

### `adam options PKG`
Show pkgsrc options for a package.

### `adam make PKG TARGET...`
Run a pkgsrc make target in a package directory.

### `adam clean`
Remove local scratch data.

### `adam autoclean`
Clean stale Adam state scratch files. Adam does not delete pkgsrc distfiles or package archives unless it can prove ownership.

### `adam check`
Check Adam state against the system package database.

### `adam doctor`
Inspect the local Adam environment.

### `adam config dump`
Print effective configuration.

### `adam config get KEY`
Print one configuration value.

### `adam config set KEY VALUE`
Record an Adam configuration value in `adam-pkg.db`.

### `adam db init`
Initialize Adam state.

### `adam db dump`
Print `adam-pkg.db`.

### `adam db resync`
Rebuild Adam's installed-package table from the system pkgdb.

### `adam db path`
Print the active database path.

### `adam edit-sources`
Open the active Adam config file in `$EDITOR`, creating a template if it does not exist.

## Notes

- Adam is source-first by default.
- `pkgin` is optional.
- `adam-pkg.db` is the authoritative Adam-managed state store.
- Some apt commands have no exact pkgsrc equivalent. Adam provides the closest useful behavior and documents the boundary.

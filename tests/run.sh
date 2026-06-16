#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMPDIR=${TMPDIR:-/tmp}
WORK="${TMPDIR}/adam-test.$$"
mkdir -p "$WORK"
WORK=$(CDPATH= cd -- "$WORK" && pwd -P)
BIN="$WORK/bin"
NO_ADMIN_BIN="$WORK/no-admin-bin"
PKGSRC="$WORK/pkgsrc"
LINKED_PKGSRC="$WORK/linked-pkgsrc"
STATE="$WORK/state"
ALT_STATE="$WORK/alt-state"
LOG="$WORK/commands.log"
COVERED="$WORK/covered"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM HUP

fail() {
    echo "not ok - $1" >&2
    exit 1
}

ok() {
    echo "ok - $1"
}

cover() {
    : > "$COVERED/$1"
}

assert_contains() {
    file=$1
    pattern=$2
    name=$3
    grep "$pattern" "$file" >/dev/null || fail "$name"
}

assert_not_contains() {
    file=$1
    pattern=$2
    name=$3
    if grep "$pattern" "$file" >/dev/null; then
        fail "$name"
    fi
}

assert_eq() {
    expected=$1
    actual=$2
    name=$3
    [ "$expected" = "$actual" ] || {
        printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
        fail "$name"
    }
}

assert_order() {
    file=$1
    first=$2
    second=$3
    name=$4
    first_line=$(awk -v p="$first" 'index($0, p) { print NR; exit }' "$file")
    second_line=$(awk -v p="$second" 'index($0, p) { print NR; exit }' "$file")
    [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ] || fail "$name"
}

assert_ok() {
    name=$1
    shift
    "$@" >/dev/null 2>"$WORK/assert.err" || {
        cat "$WORK/assert.err" >&2
        fail "$name"
    }
}

assert_fail() {
    name=$1
    shift
    if "$@" >"$WORK/assert.out" 2>"$WORK/assert.err"; then
        cat "$WORK/assert.out" >&2
        fail "$name"
    fi
}

transaction_count() {
    awk 'END { print NR + 0 }' "$STATE/tables/transactions.tsv"
}

mkdir -p "$BIN" "$NO_ADMIN_BIN" "$STATE" "$ALT_STATE" "$COVERED"
mkdir -p "$PKGSRC/category/dep" "$PKGSRC/category/app" "$PKGSRC/category/rev" "$PKGSRC/category/old" "$PKGSRC/category/exprbase" "$PKGSRC/category/gmake" "$PKGSRC/doc"
HAS_SYMLINKED_PKGSRCDIR=0
if ln -s "$PKGSRC" "$LINKED_PKGSRC" 2>/dev/null && [ -d "$LINKED_PKGSRC" ]; then
    HAS_SYMLINKED_PKGSRCDIR=1
fi
: > "$LOG"

cat > "$BIN/make" <<'EOF'
#!/bin/sh
case "$1" in
    -V)
        var=$2
        pkgpath=$(basename "$PWD")
        case "$pkgpath:$var" in
            dep:PKGNAME) echo dep-1.0 ;;
            dep:PKGBASE) echo dep ;;
            dep:COMMENT) echo dependency package ;;
            dep:LICENSE) echo mit ;;
            dep:CATEGORIES) echo category ;;
            dep:BUILD_DEPENDS) echo ;;
            dep:RUN_DEPENDS) echo ;;
            app:PKGNAME) echo app-1.0 ;;
            app:PKGBASE) echo app ;;
            app:COMMENT) echo application package ;;
            app:LICENSE) echo mit ;;
            app:CATEGORIES) echo category ;;
            app:BUILD_DEPENDS) echo 'dep>=1.0:../../category/dep' ;;
            app:RUN_DEPENDS) echo ;;
            rev:PKGNAME) echo rev-1.0 ;;
            rev:PKGBASE) echo rev ;;
            rev:COMMENT) echo reverse dependency package ;;
            rev:LICENSE) echo mit ;;
            rev:CATEGORIES) echo category ;;
            rev:BUILD_DEPENDS) echo ;;
            rev:RUN_DEPENDS) echo 'app>=1.0:../../category/app' ;;
            old:PKGNAME) echo old-1.0 ;;
            old:PKGBASE) echo old ;;
            old:COMMENT) echo old upgrade candidate ;;
            old:LICENSE) echo mit ;;
            old:CATEGORIES) echo category ;;
            old:BUILD_DEPENDS) echo ;;
            old:RUN_DEPENDS) echo ;;
            exprbase:PKGNAME) echo exprbase-2.0nb1 ;;
            exprbase:PKGBASE) echo '${PKGNAME:C/-[^-]*$//}' ;;
            exprbase:COMMENT) echo expression pkgbase package ;;
            exprbase:LICENSE) echo mit ;;
            exprbase:CATEGORIES) echo category ;;
            exprbase:BUILD_DEPENDS) echo ;;
            exprbase:RUN_DEPENDS) echo ;;
            gmake:PKGNAME) echo 'g${DISTNAME}' ;;
            gmake:DISTNAME) echo make-4.4.1 ;;
            gmake:PKGBASE) echo 'g${DISTNAME:C/-[^-]*$//}' ;;
            gmake:COMMENT) echo gmake package with expanded PKGNAME ;;
            gmake:LICENSE) echo mit ;;
            gmake:CATEGORIES) echo category ;;
            gmake:BUILD_DEPENDS) echo ;;
            gmake:RUN_DEPENDS) echo ;;
            *) echo ;;
        esac
        ;;
    install|package|configure|fetch)
        echo "$PWD $1" >> "${ADAM_TEST_LOG}"
        ;;
    show-options)
        echo "PKG_OPTIONS.test=feature"
        ;;
    *)
        echo "$PWD $*" >> "${ADAM_TEST_LOG}"
        ;;
esac
EOF
chmod +x "$BIN/make"

cat > "$BIN/pkg_info" <<'EOF'
#!/bin/sh
echo "dep-1.0 Dependency package"
echo "app-1.0 Application package"
EOF
chmod +x "$BIN/pkg_info"

cat > "$BIN/pkgin" <<'EOF'
#!/bin/sh
echo "pkgin $*" >> "${ADAM_TEST_LOG}"
exit 0
EOF
chmod +x "$BIN/pkgin"

cat > "$BIN/pkg_delete" <<'EOF'
#!/bin/sh
echo "pkg_delete $*" >> "${ADAM_TEST_LOG}"
if [ "${ADAM_TEST_DELETE_FAIL:-}" = "$1" ]; then
    exit 1
fi
exit 0
EOF
chmod +x "$BIN/pkg_delete"

cat > "$BIN/pkg_admin" <<'EOF'
#!/bin/sh
echo "pkg_admin $*" >> "${ADAM_TEST_LOG}"
echo "audit ok"
exit 0
EOF
chmod +x "$BIN/pkg_admin"

for pkg in dep app rev old exprbase gmake; do
    touch "$PKGSRC/category/$pkg/Makefile"
done
cat > "$PKGSRC/doc/CHANGES-test" <<'EOF'
Updated category/app to 1.0 for Adam tests.
EOF

run_adam() {
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$STATE/adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_adam_alt() {
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$ALT_STATE/adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_adam_linked_pkgsrc() {
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" "$ROOT/adam" \
        --pkgsrc "$LINKED_PKGSRC" \
        --db "$STATE/linked-adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_adam_no_admin() {
    PATH="$NO_ADMIN_BIN:/usr/bin:/bin" ADAM_TEST_LOG="$LOG" "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$STATE/no-admin-adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_adam_delete_fail() {
    fail_pkg=$1
    shift
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" ADAM_TEST_DELETE_FAIL="$fail_pkg" "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$STATE/adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_config_edit() {
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" EDITOR=: "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$STATE/adam-pkg.db" \
        --make make \
        --root-cmd none \
        config edit
}

run_edit_sources() {
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" EDITOR=: "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$STATE/edit-sources-adam-pkg.db" \
        --make make \
        --root-cmd none \
        --config "$WORK/adam.conf" \
        edit-sources
}

HELP_STATE="$WORK/help-state"
PATH="$BIN:$PATH" "$ROOT/adam" \
    --pkgsrc "$PKGSRC" \
    --db "$HELP_STATE/adam-pkg.db" \
    --make make \
    --root-cmd none \
    help > "$WORK/help.out"
cover help
assert_contains "$WORK/help.out" "Usage:" "help prints overview"
[ ! -e "$HELP_STATE" ] || fail "help does not create state"

run_adam help install > "$WORK/help-install.out"
assert_contains "$WORK/help-install.out" "adam install PKG..." "help install prints install usage"
run_adam help mark > "$WORK/help-mark.out"
assert_contains "$WORK/help-mark.out" "manual|auto|hold|unhold" "help mark prints mark subcommands"
run_adam help rm > "$WORK/help-rm.out"
assert_contains "$WORK/help-rm.out" "adam remove PKG..." "help rm resolves remove usage"
assert_fail "unknown help topic fails" run_adam help missing-topic
assert_contains "$WORK/assert.err" "unknown help topic" "unknown help topic error is clear"
ok "help command supports overview and command topics"

run_adam update >/dev/null
cover update
[ -s "$STATE/tables/available.tsv" ] || fail "update creates available index"
awk -F '\t' '$1 == "gmake" && $2 == "gmake-4.4.1" && $4 == "4.4.1" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/available.tsv" || fail "simple variable expansion resolves gmake metadata"
ok "update creates available index"

plan=$(run_adam plan app)
cover plan
expected=$(printf 'category/dep\ncategory/app')
assert_eq "$expected" "$plan" "plan orders dependencies before target"
ok "plan orders dependencies before target"

if [ "$HAS_SYMLINKED_PKGSRCDIR" -eq 1 ]; then
    run_adam_linked_pkgsrc update >/dev/null
    linked_plan=$(run_adam_linked_pkgsrc plan app)
    assert_eq "$expected" "$linked_plan" "plan works with symlinked pkgsrc root"
    ok "plan works with symlinked pkgsrc root"
else
    ok "symlinked pkgsrc root test skipped because symlinks are unavailable"
fi

tx_before=$(transaction_count)
run_adam --dry-run install app > "$WORK/dryrun.out"
cover install
assert_contains "$WORK/dryrun.out" "category/dep" "dry run includes dependency"
assert_contains "$WORK/dryrun.out" "category/app" "dry run includes target"
tx_after=$(transaction_count)
assert_eq "$tx_before" "$tx_after" "dry-run install leaves transactions unchanged"
ok "dry-run install prints source build commands"

run_adam install app >/dev/null
assert_contains "$LOG" "category/dep install" "source install runs dependency install"
assert_contains "$LOG" "category/app install" "source install runs target install"
awk -F '\t' '$1 == "dep" && $7 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "dependency is recorded automatic"
awk -F '\t' '$1 == "app" && $7 == "0" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "requested package is recorded manual"
ok "source install records dependency-first commands"

run_adam install exprbase >/dev/null
assert_contains "$LOG" "category/exprbase install" "expression pkgbase package builds"
awk -F '\t' '$1 == "exprbase" && $2 == "exprbase-2.0nb1" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "expression pkgbase resolves through PKGNAME"
run_adam remove exprbase >/dev/null
ok "expression PKGBASE metadata resolves through PKGNAME"

run_adam install gmake >/dev/null
assert_contains "$LOG" "category/gmake install" "gmake package builds"
awk -F '\t' '$1 == "gmake" && $2 == "gmake-4.4.1" && $4 == "4.4.1" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "gmake PKGNAME expands DISTNAME"
run_adam show gmake > "$WORK/show-gmake.out"
assert_contains "$WORK/show-gmake.out" "Package: gmake-4.4.1" "show renders expanded gmake metadata"
run_adam remove gmake >/dev/null
ok "simple make variable expansion resolves pkgname metadata"

run_adam reinstall app >/dev/null
cover reinstall
ok "reinstall reuses install path"

tx_before=$(transaction_count)
run_adam --dry-run build app > "$WORK/build-dry.out"
assert_contains "$WORK/build-dry.out" "package" "dry-run build prints package target"
tx_after=$(transaction_count)
assert_eq "$tx_before" "$tx_after" "dry-run build leaves transactions unchanged"

run_adam build app >/dev/null
cover build
assert_contains "$LOG" "category/app package" "build invokes package target"
ok "build invokes pkgsrc package target"

run_adam --binary update >/dev/null
assert_contains "$LOG" "pkgin update" "binary update uses pkgin"
ok "binary update uses pkgin"

run_adam --binary install app >/dev/null
assert_contains "$LOG" "pkgin install app" "binary install uses pkgin"
ok "binary install uses pkgin"

run_adam --binary download app >/dev/null
cover download
assert_contains "$LOG" "pkgin download app" "binary download uses pkgin"
ok "binary download uses pkgin"

run_adam --binary remove app >/dev/null
assert_contains "$LOG" "pkgin remove app" "binary remove uses pkgin"
ok "binary remove uses pkgin"

run_adam --binary upgrade >/dev/null
assert_contains "$LOG" "pkgin upgrade" "binary upgrade uses pkgin"
ok "binary upgrade uses pkgin"

run_adam --binary autoremove >/dev/null
cover autoremove
assert_contains "$LOG" "pkgin autoremove" "binary autoremove uses pkgin"
ok "binary autoremove uses pkgin"

run_adam search app > "$WORK/search.out"
cover search
assert_contains "$WORK/search.out" "app" "search finds app"
ok "search finds package metadata"

run_adam show app > "$WORK/show.out"
cover show
assert_contains "$WORK/show.out" "Package: app-1.0" "show renders metadata"
ok "show renders metadata"

run_adam source app > "$WORK/source.out"
cover source
assert_contains "$WORK/source.out" "category/app" "source resolves pkgsrc path"
ok "source resolves pkgsrc path"

run_adam list --all-versions > "$WORK/list-all.out"
cover list
assert_contains "$WORK/list-all.out" "category/app" "list --all-versions shows available"
ok "list --all-versions shows available packages"

run_adam list --installed > "$WORK/list-installed.out"
assert_contains "$WORK/list-installed.out" "dep-1.0" "list --installed shows installed dependency"
ok "list --installed shows installed packages"

printf 'old\told-0.9\tcategory/old\t0.9\tinstalled\tsource\t0\t\t2026\t2026\n' >> "$STATE/tables/installed.tsv"
run_adam list --upgradeable > "$WORK/list-upgradeable.out"
assert_contains "$WORK/list-upgradeable.out" "old 0.9 1.0" "list --upgradeable shows version mismatch"
ok "list --upgradeable shows upgrade candidates"

run_adam depends app > "$WORK/depends.out"
cover depends
assert_contains "$WORK/depends.out" "category/dep" "depends shows pkgsrc dependency"
ok "depends shows pkgsrc dependency"

run_adam rdepends app > "$WORK/rdepends.out"
cover rdepends
assert_contains "$WORK/rdepends.out" "category/rev" "rdepends shows reverse dependency"
ok "rdepends shows reverse dependency"

run_adam install app >/dev/null
run_adam policy app > "$WORK/policy.out"
cover policy
assert_contains "$WORK/policy.out" "Candidate: 1.0" "policy shows candidate"
assert_contains "$WORK/policy.out" "Installed: 1.0" "policy shows installed version"
ok "policy shows installed and candidate"

run_adam build-dep app > "$WORK/build-dep.out"
cover build-dep
assert_contains "$WORK/build-dep.out" "category/dep" "build-dep shows dependency"
ok "build-dep shows dependencies"

run_adam --dry-run satisfy 'app>=1.0' > "$WORK/satisfy.out"
cover satisfy
assert_contains "$WORK/satisfy.out" "category/app" "satisfy plans package"
ok "satisfy parses dependency expression"

run_adam indextargets > "$WORK/indextargets.out"
cover indextargets
assert_contains "$WORK/indextargets.out" "database" "indextargets lists database"
ok "indextargets lists database"

run_adam changelog app > "$WORK/changelog.out"
cover changelog
assert_contains "$WORK/changelog.out" "category/app" "changelog finds package entry"
ok "changelog searches pkgsrc doc entries"

run_adam madison app > "$WORK/madison.out"
cover madison
assert_contains "$WORK/madison.out" "app | 1.0 | pkgsrc:category/app" "madison renders source version"
ok "madison renders source version"

run_adam options app > "$WORK/options.out"
cover options
assert_contains "$WORK/options.out" "PKG_OPTIONS.test=feature" "options invokes make show-options"
ok "options invokes make show-options"

run_adam --dry-run make app configure > "$WORK/make.out"
cover make
assert_contains "$WORK/make.out" "make configure" "make command supports dry-run"
ok "make command supports dry-run"

run_adam audit > "$WORK/audit.out"
cover audit
assert_contains "$WORK/audit.out" "audit ok" "audit prints pkg_admin output"
assert_contains "$LOG" "pkg_admin audit" "audit invokes pkg_admin"
ok "audit invokes pkg_admin"

assert_fail "audit fails without pkg_admin" run_adam_no_admin audit
assert_contains "$WORK/assert.err" "pkg_admin unavailable" "audit missing error is clear"
ok "audit reports unavailable pkg_admin"

run_adam mark manual app
run_adam mark showmanual > "$WORK/showmanual.out"
cover mark
assert_contains "$WORK/showmanual.out" "app" "mark showmanual reports manual"
ok "mark manual/showmanual works"

run_adam mark auto app
run_adam mark showauto > "$WORK/showauto.out"
assert_contains "$WORK/showauto.out" "app" "mark showauto reports auto"
ok "mark auto/showauto works"

run_adam mark hold app
run_adam mark showhold > "$WORK/showhold.out"
assert_contains "$WORK/showhold.out" "app" "mark showhold reports hold"
ok "mark hold/showhold works"

assert_fail "hold blocks source install" run_adam install app
assert_contains "$WORK/assert.err" "package is on hold" "hold error is clear"
ok "hold blocks source install"

run_adam --ignore-hold --dry-run install app >/dev/null
ok "ignore-hold allows planning"

run_adam mark minimize-manual > "$WORK/minimize.out"
assert_contains "$WORK/minimize.out" "nothing to do" "minimize-manual reports no-op clearly"
ok "mark minimize-manual handles no-op"

run_adam mark unhold app
run_adam mark showhold > "$WORK/showhold-after.out"
assert_not_contains "$WORK/showhold-after.out" "app" "unhold removes hold"
ok "mark unhold clears hold"

tx_before=$(transaction_count)
run_adam --dry-run remove category/app > "$WORK/remove-dry.out"
assert_contains "$WORK/remove-dry.out" "pkg_delete" "dry-run remove prints delete command"
run_adam list --installed > "$WORK/remove-dry-list.out"
assert_contains "$WORK/remove-dry-list.out" "app-1.0" "dry-run remove keeps installed state"
tx_after=$(transaction_count)
assert_eq "$tx_before" "$tx_after" "dry-run remove leaves transactions unchanged"

run_adam_delete_fail app remove category/app >/dev/null || true
assert_contains "$LOG" "pkg_delete app" "remove resolves pkgbase before deleting"
run_adam list --installed > "$WORK/remove-fail-list.out"
assert_contains "$WORK/remove-fail-list.out" "app-1.0" "failed remove keeps installed state"

run_adam remove category/app >/dev/null
cover remove
assert_contains "$LOG" "pkg_delete app" "remove invokes pkg_delete"
ok "remove invokes pkg_delete"

run_adam rm dep >/dev/null
cover rm
assert_contains "$LOG" "pkg_delete dep" "rm alias invokes pkg_delete"
ok "rm alias invokes remove"

run_adam install app >/dev/null
run_adam purge app >/dev/null
cover purge
assert_contains "$LOG" "pkg_delete app" "purge invokes removal path"
ok "purge invokes removal path"

run_adam autoremove >/dev/null
assert_contains "$LOG" "pkg_delete dep" "autoremove deletes orphan automatic dependency"
run_adam list --installed > "$WORK/autoremove-list.out"
assert_not_contains "$WORK/autoremove-list.out" "dep-1.0" "autoremove removes dependency from state"
ok "autoremove removes orphan automatic packages"

run_adam install app >/dev/null
run_adam remove category/app >/dev/null
run_adam --dry-run autoremove > "$WORK/autoremove-dry.out"
assert_contains "$WORK/autoremove-dry.out" "pkg_delete dep" "autoremove dry-run prints deletion"
run_adam list --installed > "$WORK/autoremove-dry-list.out"
assert_contains "$WORK/autoremove-dry-list.out" "dep-1.0" "autoremove dry-run keeps state"
ok "autoremove dry-run leaves state unchanged"

: > "$LOG"
: > "$STATE/tables/installed.tsv"
printf 'dep\tdep-1.0\tcategory/dep\t1.0\tinstalled\tsource\t1\t\t2026\t2026\n' >> "$STATE/tables/installed.tsv"
printf 'app\tapp-1.0\tcategory/app\t1.0\tinstalled\tsource\t1\t\t2026\t2026\n' >> "$STATE/tables/installed.tsv"
run_adam autoremove > "$WORK/autoremove-order.out"
assert_order "$LOG" "pkg_delete app" "pkg_delete dep" "autoremove deletes dependents before dependencies"
ok "autoremove removes orphan automatic packages in reverse order"

run_adam install app >/dev/null
run_adam remove category/app >/dev/null
run_adam mark hold dep
run_adam autoremove > "$WORK/autoremove-hold.out"
assert_contains "$WORK/autoremove-hold.out" "nothing to do" "held automatic package is skipped"
run_adam mark unhold dep
ok "autoremove respects holds"

run_adam mark manual dep
awk -F '\t' '$1 == "dep" && $7 == "0" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "mark manual updates automatic flag"
run_adam mark auto dep
awk -F '\t' '$1 == "dep" && $7 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "mark auto updates automatic flag"
ok "mark manual/auto updates installed automatic flag"

run_adam install app >/dev/null
run_adam mark manual app dep
run_adam mark minimize-manual > "$WORK/minimize-dep.out"
assert_contains "$WORK/minimize-dep.out" "dep" "minimize-manual marks dependency auto"
awk -F '\t' '$1 == "dep" && $7 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$STATE/tables/installed.tsv" || fail "minimize-manual updates dependency automatic flag"
ok "mark minimize-manual minimizes reachable dependencies"

run_adam install app >/dev/null
tx_before=$(transaction_count)
run_adam --dry-run upgrade > "$WORK/upgrade-dry.out"
assert_contains "$WORK/upgrade-dry.out" "upgraded" "dry-run upgrade reports planned upgrade"
tx_after=$(transaction_count)
assert_eq "$tx_before" "$tx_after" "dry-run upgrade leaves transactions unchanged"

run_adam upgrade >/dev/null
cover upgrade
assert_contains "$LOG" "category/app install" "upgrade reinstalls installed app"
ok "upgrade walks installed packages"

run_adam full-upgrade >/dev/null
cover full-upgrade
ok "full-upgrade aliases upgrade"

run_adam dist-upgrade >/dev/null
cover dist-upgrade
ok "dist-upgrade aliases full-upgrade"

run_adam db init > "$WORK/db-init.out"
cover db
assert_contains "$WORK/db-init.out" "initialized" "db init initializes state"
ok "db init initializes state"

run_adam db path > "$WORK/dbpath.out"
assert_contains "$WORK/dbpath.out" "$STATE/adam-pkg.db" "db path reports configured db"
ok "db path reports configured db"

run_adam db tables > "$WORK/dbtables.out"
assert_contains "$WORK/dbtables.out" "available.tsv" "db tables lists table files"
ok "db tables lists table files"

run_adam db dump > "$WORK/dbdump.out"
assert_contains "$WORK/dbdump.out" "\[available\]" "db dump contains available section"
ok "db dump renders adam-pkg.db"

run_adam db resync >/dev/null
run_adam list --installed > "$WORK/resync-list.out"
assert_contains "$WORK/resync-list.out" "app-1.0" "db resync imports pkg_info"
ok "db resync imports pkg_info state"

run_adam config dump > "$WORK/config-dump.out"
cover config
assert_contains "$WORK/config-dump.out" "ADAM_PKGSRCDIR" "config dump reports keys"
ok "config dump reports keys"

run_adam config get ADAM_PKGSRCDIR > "$WORK/config-get.out"
assert_contains "$WORK/config-get.out" "$PKGSRC" "config get reports pkgsrc path"
ok "config get reports pkgsrc path"

run_adam config set TEST_KEY TEST_VALUE >/dev/null
run_adam db dump > "$WORK/config-set-dump.out"
assert_contains "$WORK/config-set-dump.out" "TEST_KEY" "config set persists key"
ok "config set persists key"

run_config_edit >/dev/null
ok "config edit honors EDITOR"

run_adam check > "$WORK/check.out"
cover check
assert_contains "$WORK/check.out" "ok" "check reports synced state"
ok "check reports synced state"

run_adam check --repair > "$WORK/check-repair.out"
assert_contains "$WORK/check-repair.out" "repaired" "check --repair refreshes index"
ok "check --repair refreshes index"

run_adam doctor > "$WORK/doctor.out"
cover doctor
assert_contains "$WORK/doctor.out" "state dir:" "doctor reports state"
ok "doctor reports environment"

run_adam stats > "$WORK/stats.out"
cover stats
assert_contains "$WORK/stats.out" "installed" "stats reports installed count"
assert_contains "$WORK/stats.out" "available" "stats reports available count"
ok "stats reports counts"

run_adam dumpavail > "$WORK/dumpavail.out"
cover dumpavail
assert_contains "$WORK/dumpavail.out" "category/app" "dumpavail prints available table"
ok "dumpavail prints available table"

run_adam pkgnames app > "$WORK/pkgnames.out"
cover pkgnames
assert_contains "$WORK/pkgnames.out" "app-1.0" "pkgnames filters names"
ok "pkgnames filters names"

run_adam clean > "$WORK/clean.out"
cover clean
assert_contains "$WORK/clean.out" "cleaned" "clean reports cleaned"
ok "clean reports cleaned"

run_adam autoclean > "$WORK/autoclean.out"
cover autoclean
assert_contains "$WORK/autoclean.out" "cleaned" "autoclean reports cleaned count"
ok "autoclean cleans Adam temp files conservatively"

run_edit_sources > "$WORK/edit-sources.out"
cover edit-sources
assert_contains "$WORK/adam.conf" "ADAM_PKGSRCDIR" "edit-sources creates config template"
ok "edit-sources creates and opens config file"

download_tx_before=$(awk -F '\t' '$2 == "download" { count++ } END { print count + 0 }' "$STATE/tables/transactions.tsv")
run_adam --dry-run download app > "$WORK/download-dry.out"
assert_contains "$WORK/download-dry.out" "make fetch" "source download dry-run prints fetch target"
download_tx_after=$(awk -F '\t' '$2 == "download" { count++ } END { print count + 0 }' "$STATE/tables/transactions.tsv")
assert_eq "$download_tx_before" "$download_tx_after" "source download dry-run leaves transactions unchanged"
ok "source download dry-run does not mutate transactions"

run_adam download app > "$WORK/download.out"
assert_contains "$LOG" "category/app fetch" "source download runs fetch target"
ok "source download fetches package distfiles"

assert_fail "unknown command fails" run_adam no-such-command
assert_contains "$WORK/assert.err" "unknown command" "unknown command error is clear"
ok "unknown command fails clearly"

assert_fail "install missing args fails" run_adam install
assert_contains "$WORK/assert.err" "install requires" "install missing args error is clear"
ok "missing install args fail clearly"

assert_fail "unknown config key fails" run_adam config get UNKNOWN_KEY
assert_contains "$WORK/assert.err" "unknown config key" "unknown config key error is clear"
ok "unknown config key fails clearly"

assert_fail "unknown package fails" run_adam show missing
assert_contains "$WORK/assert.err" "unknown package" "unknown package error is clear"
ok "unknown package fails clearly"

run_adam_alt update >/dev/null
run_adam_alt --dry-run satisfy 'app>=1.0' >/dev/null
ok "alternate state can satisfy dependency expressions"

EXPECTED_COMMANDS="help update install reinstall remove rm purge upgrade full-upgrade dist-upgrade autoremove search show list depends rdepends policy mark build plan source download build-dep satisfy indextargets changelog madison audit options make clean autoclean check doctor stats dumpavail pkgnames config db edit-sources"
for cmd in $EXPECTED_COMMANDS; do
    [ -f "$COVERED/$cmd" ] || fail "missing command coverage: $cmd"
done
ok "all public dispatch commands are covered"

sh -n "$ROOT/adam"
ok "adam passes sh -n"

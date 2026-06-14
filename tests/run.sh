#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMPDIR=${TMPDIR:-/tmp}
WORK="${TMPDIR}/adam-test.$$"
BIN="$WORK/bin"
PKGSRC="$WORK/pkgsrc"
STATE="$WORK/state"
LOG="$WORK/commands.log"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM HUP

mkdir -p "$BIN" "$PKGSRC/category/dep" "$PKGSRC/category/app" "$STATE"
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
            *) echo ;;
        esac
        ;;
    install|package)
        echo "$PWD $1" >> "${ADAM_TEST_LOG}"
        ;;
    *)
        echo "$PWD $*" >> "${ADAM_TEST_LOG}"
        ;;
esac
EOF
chmod +x "$BIN/make"

cat > "$BIN/pkg_info" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$BIN/pkg_info"

cat > "$BIN/pkgin" <<'EOF'
#!/bin/sh
echo "pkgin $*" >> "${ADAM_TEST_LOG}"
exit 0
EOF
chmod +x "$BIN/pkgin"

touch "$PKGSRC/category/dep/Makefile" "$PKGSRC/category/app/Makefile"

fail() {
    echo "not ok - $1" >&2
    exit 1
}

ok() {
    echo "ok - $1"
}

run_adam() {
    PATH="$BIN:$PATH" ADAM_TEST_LOG="$LOG" "$ROOT/adam" \
        --pkgsrc "$PKGSRC" \
        --db "$STATE/adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_adam update >/dev/null
[ -s "$STATE/tables/available.tsv" ] || fail "update creates available index"
ok "update creates available index"

plan=$(run_adam plan app)
expected=$(printf 'category/dep\ncategory/app')
[ "$plan" = "$expected" ] || {
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$plan" >&2
    fail "plan orders dependencies before target"
}
ok "plan orders dependencies before target"

run_adam --dry-run install app > "$WORK/dryrun.out"
grep "category/dep" "$WORK/dryrun.out" >/dev/null || fail "dry run includes dependency"
grep "category/app" "$WORK/dryrun.out" >/dev/null || fail "dry run includes target"
ok "dry-run install prints source build commands"

run_adam --binary install app >/dev/null
grep "pkgin install app" "$LOG" >/dev/null || fail "binary mode uses pkgin"
ok "binary mode uses pkgin"

run_adam mark hold app
if run_adam install app >/dev/null 2>"$WORK/hold.err"; then
    fail "hold blocks source install"
fi
grep "package is on hold" "$WORK/hold.err" >/dev/null || fail "hold error is clear"
ok "hold blocks source install"

run_adam --ignore-hold --dry-run install app >/dev/null
ok "ignore-hold allows planning"

run_adam show app > "$WORK/show.out"
grep "Package: app-1.0" "$WORK/show.out" >/dev/null || fail "show renders metadata"
ok "show renders metadata"

run_adam depends app > "$WORK/depends.out"
grep "category/dep" "$WORK/depends.out" >/dev/null || fail "depends shows pkgsrc dependency"
ok "depends shows pkgsrc dependency"

sh -n "$ROOT/adam"
ok "adam passes sh -n"

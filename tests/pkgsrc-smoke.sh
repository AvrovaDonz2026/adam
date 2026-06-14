#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE="${1:-smoke}"
PKGSRC_DIR="${PKGSRC_DIR:-/tmp/pkgsrc}"
STATE_DIR="${STATE_DIR:-/tmp/adam-pkgsrc-smoke-state}"
PKGSRC_TARBALL="${PKGSRC_TARBALL:-https://cdn.NetBSD.org/pub/pkgsrc/stable/pkgsrc.tar.xz}"
TEST_PKG="${TEST_PKG:-pkgtools/digest}"

fail() {
    echo "not ok - $1" >&2
    exit 1
}

ok() {
    echo "ok - $1"
}

fetch_file() {
    url=$1
    out=$2
    if command -v ftp >/dev/null 2>&1; then
        ftp -o "$out" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out" "$url"
    else
        fail "no fetch tool found"
    fi
}

ensure_pkgsrc() {
    if [ -d "$PKGSRC_DIR/$TEST_PKG" ]; then
        return 0
    fi

    archive="/tmp/pkgsrc.tar.xz"
    rm -rf "$PKGSRC_DIR" /tmp/pkgsrc
    fetch_file "$PKGSRC_TARBALL" "$archive"
    tar -C /tmp -xJf "$archive"
    [ -d /tmp/pkgsrc ] || fail "pkgsrc archive did not extract to /tmp/pkgsrc"
    if [ "$PKGSRC_DIR" != /tmp/pkgsrc ]; then
        mv /tmp/pkgsrc "$PKGSRC_DIR"
    fi
}

run_adam() {
    "$ROOT/adam" \
        --pkgsrc "$PKGSRC_DIR" \
        --db "$STATE_DIR/adam-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

run_adam_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        run_adam "$@"
        return 0
    fi

    command -v sudo >/dev/null 2>&1 || fail "sudo is required for real pkgsrc builds"

    sudo "$ROOT/adam" \
        --pkgsrc "$PKGSRC_DIR" \
        --db "$STATE_DIR/adam-root-pkg.db" \
        --make make \
        --root-cmd none \
        "$@"
}

ensure_pkgsrc

sh -n "$ROOT/adam"
ok "adam passes sh -n"

sh "$ROOT/tests/run.sh"
ok "fake-tree tests pass on this platform"

run_adam source "$TEST_PKG" > /tmp/adam-source.out
grep "$TEST_PKG" /tmp/adam-source.out >/dev/null || fail "source resolves $TEST_PKG"
ok "source resolves $TEST_PKG"

run_adam plan "$TEST_PKG" > /tmp/adam-plan.out
grep "$TEST_PKG" /tmp/adam-plan.out >/dev/null || fail "plan includes $TEST_PKG"
ok "plan includes $TEST_PKG"

run_adam --dry-run install "$TEST_PKG" > /tmp/adam-dry-run.out
grep "$TEST_PKG" /tmp/adam-dry-run.out >/dev/null || fail "dry-run install references $TEST_PKG"
ok "dry-run install references $TEST_PKG"

case "$MODE" in
    smoke)
        ;;
    build)
        run_adam_as_root build "$TEST_PKG"
        ok "real pkgsrc build completed for $TEST_PKG"
        ;;
    *)
        fail "unknown mode: $MODE"
        ;;
esac

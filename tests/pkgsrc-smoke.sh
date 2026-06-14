#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE="${1:-smoke}"
PKGSRC_DIR="${PKGSRC_DIR:-/tmp/pkgsrc}"
STATE_DIR="${STATE_DIR:-/tmp/adam-pkgsrc-smoke-state}"
PKGSRC_TARBALL="${PKGSRC_TARBALL:-https://cdn.NetBSD.org/pub/pkgsrc/stable/pkgsrc.tar.gz}"
TEST_PKG="${TEST_PKG:-misc/figlet}"
PKGSRC_BOOTSTRAP="${PKGSRC_BOOTSTRAP:-none}"
ADAM_TEST_MAKE_CMD="${ADAM_TEST_MAKE_CMD:-}"
ADAM_TEST_BUILD_ROOT="${ADAM_TEST_BUILD_ROOT:-0}"

case "$PKGSRC_BOOTSTRAP" in
    unprivileged)
        PKGSRC_PREFIX="${PKGSRC_PREFIX:-${HOME}/pkg}"
        PKGSRC_PKGDBDIR="${PKGSRC_PKGDBDIR:-${PKGSRC_PREFIX}/pkgdb}"
        PKGSRC_VARBASE="${PKGSRC_VARBASE:-${PKGSRC_PREFIX}/var}"
        ;;
    privileged)
        PKGSRC_PREFIX="${PKGSRC_PREFIX:-/usr/pkg}"
        PKGSRC_PKGDBDIR="${PKGSRC_PKGDBDIR:-${PKGSRC_PREFIX}/pkgdb}"
        PKGSRC_VARBASE="${PKGSRC_VARBASE:-${PKGSRC_PREFIX}/var}"
        ;;
    none)
        PKGSRC_PREFIX="${PKGSRC_PREFIX:-}"
        PKGSRC_PKGDBDIR="${PKGSRC_PKGDBDIR:-}"
        PKGSRC_VARBASE="${PKGSRC_VARBASE:-}"
        ;;
    *)
        echo "not ok - unknown bootstrap mode: $PKGSRC_BOOTSTRAP" >&2
        exit 1
        ;;
esac

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

    archive="/tmp/pkgsrc.tarball"
    rm -rf "$PKGSRC_DIR" /tmp/pkgsrc
    fetch_file "$PKGSRC_TARBALL" "$archive"
    case "$PKGSRC_TARBALL" in
        *.tar.xz) tar -C /tmp -xJf "$archive" ;;
        *.tar.gz|*.tgz) tar -C /tmp -xzf "$archive" ;;
        *) tar -C /tmp -xf "$archive" ;;
    esac
    [ -d /tmp/pkgsrc ] || fail "pkgsrc archive did not extract to /tmp/pkgsrc"
    if [ "$PKGSRC_DIR" != /tmp/pkgsrc ]; then
        mv /tmp/pkgsrc "$PKGSRC_DIR"
    fi
}

root_exec() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return 0
    fi

    if command -v doas >/dev/null 2>&1 && doas -n true >/dev/null 2>&1; then
        doas -n "$@"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        sudo -n "$@"
        return 0
    fi

    fail "passwordless doas or sudo is required"
}

bootstrap_pkgsrc() {
    case "$PKGSRC_BOOTSTRAP" in
        none)
            return 0
            ;;
        unprivileged)
            if [ -x "$PKGSRC_PREFIX/bin/bmake" ]; then
                return 0
            fi
            (
                cd "$PKGSRC_DIR/bootstrap"
                ./bootstrap --unprivileged \
                    --prefix "$PKGSRC_PREFIX" \
                    --pkgdbdir "$PKGSRC_PKGDBDIR" \
                    --varbase "$PKGSRC_VARBASE"
            )
            ;;
        privileged)
            if [ -x "$PKGSRC_PREFIX/bin/bmake" ]; then
                return 0
            fi
            root_exec env \
                PKGSRC_DIR="$PKGSRC_DIR" \
                PKGSRC_PREFIX="$PKGSRC_PREFIX" \
                PKGSRC_PKGDBDIR="$PKGSRC_PKGDBDIR" \
                PKGSRC_VARBASE="$PKGSRC_VARBASE" \
                sh -c 'cd "$PKGSRC_DIR/bootstrap" && ./bootstrap --prefix "$PKGSRC_PREFIX" --pkgdbdir "$PKGSRC_PKGDBDIR" --varbase "$PKGSRC_VARBASE"'
            ;;
    esac
}

activate_pkgsrc_prefix() {
    if [ -n "$PKGSRC_PREFIX" ]; then
        PATH="$PKGSRC_PREFIX/bin:$PKGSRC_PREFIX/sbin:$PATH"
        export PATH
    fi
}

adam_make_cmd() {
    if [ -n "$ADAM_TEST_MAKE_CMD" ]; then
        printf '%s' "$ADAM_TEST_MAKE_CMD"
    elif [ -n "$PKGSRC_PREFIX" ] && [ -x "$PKGSRC_PREFIX/bin/bmake" ]; then
        printf '%s' "$PKGSRC_PREFIX/bin/bmake"
    elif command -v bmake >/dev/null 2>&1; then
        printf '%s' bmake
    else
        printf '%s' make
    fi
}

run_adam() {
    makecmd=$(adam_make_cmd)
    "$ROOT/adam" \
        --pkgsrc "$PKGSRC_DIR" \
        --db "$STATE_DIR/adam-pkg.db" \
        --make "$makecmd" \
        --root-cmd none \
        "$@"
}

run_adam_as_root() {
    makecmd=$(adam_make_cmd)
    root_exec env PATH="$PATH" "$ROOT/adam" \
        --pkgsrc "$PKGSRC_DIR" \
        --db "$STATE_DIR/adam-root-pkg.db" \
        --make "$makecmd" \
        --root-cmd none \
        "$@"
}

ensure_pkgsrc
bootstrap_pkgsrc
activate_pkgsrc_prefix

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
        if [ "$ADAM_TEST_BUILD_ROOT" -eq 1 ]; then
            run_adam_as_root build "$TEST_PKG"
        else
            run_adam build "$TEST_PKG"
        fi
        ok "real pkgsrc build completed for $TEST_PKG"
        ;;
    *)
        fail "unknown mode: $MODE"
        ;;
esac

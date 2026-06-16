#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE="${1:-smoke}"
PKGSRC_DIR="${PKGSRC_DIR:-/tmp/pkgsrc}"
STATE_DIR="${STATE_DIR:-/tmp/adam-pkgsrc-smoke-state}"
PKGSRC_TARBALL="${PKGSRC_TARBALL:-https://cdn.NetBSD.org/pub/pkgsrc/stable/pkgsrc.tar.gz}"
PKGSRC_TARBALLS="${PKGSRC_TARBALLS:-$PKGSRC_TARBALL https://ftp.NetBSD.org/pub/pkgsrc/stable/pkgsrc.tar.gz}"
TEST_PKG="${TEST_PKG:-misc/figlet}"
PKGSRC_BOOTSTRAP="${PKGSRC_BOOTSTRAP:-none}"
ADAM_TEST_MAKE_CMD="${ADAM_TEST_MAKE_CMD:-}"
ADAM_TEST_BUILD_ROOT="${ADAM_TEST_BUILD_ROOT:-0}"
BMAKE_MIN_VERSION="${BMAKE_MIN_VERSION:-20240711}"
PKGSRC_FETCHED_TARBALL=""

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
    partial="${out}.part"
    attempts=0
    while [ "$attempts" -lt 5 ]; do
        attempts=$((attempts + 1))
        printf 'fetching pkgsrc: %s (attempt %s)\n' "$url" "$attempts"
        if command -v curl >/dev/null 2>&1; then
            if curl -fL --retry 3 --retry-delay 5 --retry-connrefused -C - "$url" -o "$partial"; then
                mv "$partial" "$out"
                PKGSRC_FETCHED_TARBALL="$url"
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -c -O "$partial" "$url"; then
                mv "$partial" "$out"
                PKGSRC_FETCHED_TARBALL="$url"
                return 0
            fi
        elif command -v ftp >/dev/null 2>&1; then
            if ftp -o "$partial" "$url"; then
                mv "$partial" "$out"
                PKGSRC_FETCHED_TARBALL="$url"
                return 0
            fi
        else
            fail "no fetch tool found"
        fi
        rm -f "$partial"
        [ "$attempts" -lt 5 ] || return 1
        sleep $((attempts * 5))
    done
}

fetch_pkgsrc_archive() {
    out=$1
    for url in $PKGSRC_TARBALLS; do
        if fetch_file "$url" "$out"; then
            return 0
        fi
        rm -f "$out"
    done
    return 1
}

ensure_pkgsrc() {
    if [ -d "$PKGSRC_DIR/$TEST_PKG" ]; then
        return 0
    fi

    pkgsrc_parent=$(dirname "$PKGSRC_DIR")
    archive="${pkgsrc_parent}/pkgsrc.tarball"
    extract_parent="${pkgsrc_parent}/pkgsrc-extract.$$"

    mkdir -p "$pkgsrc_parent"
    rm -rf "$PKGSRC_DIR" "$extract_parent"
    mkdir -p "$extract_parent"
    fetch_pkgsrc_archive "$archive" || fail "unable to fetch pkgsrc archive"
    case "$PKGSRC_FETCHED_TARBALL" in
        *.tar.xz) tar -C "$extract_parent" -xJf "$archive" ;;
        *.tar.gz|*.tgz) tar -C "$extract_parent" -xzf "$archive" ;;
        *) tar -C "$extract_parent" -xf "$archive" ;;
    esac
    [ -d "$extract_parent/pkgsrc" ] || fail "pkgsrc archive did not extract to $extract_parent/pkgsrc"
    mv "$extract_parent/pkgsrc" "$PKGSRC_DIR"
    rm -rf "$extract_parent" "$archive"
}

show_disk_space() {
    printf 'pkgsrc dir: %s\n' "$PKGSRC_DIR"
    printf 'state dir: %s\n' "$STATE_DIR"
    df -h "$PKGSRC_DIR" "$(dirname "$STATE_DIR")" /tmp 2>/dev/null || df -h
}

root_exec() {
    prefix=$(root_prefix) || fail "passwordless doas or sudo is required"
    if [ -z "$prefix" ]; then
        "$@"
    else
        $prefix "$@"
    fi
}

root_prefix() {
    if [ "$(id -u)" -eq 0 ]; then
        printf '%s\n' ""
        return 0
    fi

    if command -v doas >/dev/null 2>&1 && doas -n true >/dev/null 2>&1; then
        printf '%s\n' "doas -n"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        printf '%s\n' "sudo -n"
        return 0
    fi

    return 1
}

pkgsrc_su_cmd() {
    prefix=$(root_prefix) || return 1
    if [ -z "$prefix" ]; then
        printf '%s\n' "sh -c"
    else
        printf '%s\n' "$prefix sh -c"
    fi
}

bmake_is_current() {
    makecmd="$1"
    [ -x "$makecmd" ] || return 1
    version=$("$makecmd" -V MAKE_VERSION 2>/dev/null || true)
    case "$version" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$version" -ge "$BMAKE_MIN_VERSION" ]
}

bootstrap_pkgsrc() {
    case "$PKGSRC_BOOTSTRAP" in
        none)
            return 0
            ;;
        unprivileged)
            if bmake_is_current "$PKGSRC_PREFIX/bin/bmake"; then
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
            if bmake_is_current "$PKGSRC_PREFIX/bin/bmake"; then
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
        PATH="$PKGSRC_PREFIX/bin:$PKGSRC_PREFIX/sbin:/usr/pkg/bin:/usr/pkg/sbin:/usr/sbin:/sbin:$PATH"
    else
        PATH="/usr/pkg/bin:/usr/pkg/sbin:/usr/sbin:/sbin:$PATH"
    fi
    export PATH
}

pkgsrc_make_var() {
    var="$1"
    makecmd=$(adam_make_cmd)
    if [ -d "$PKGSRC_DIR/$TEST_PKG" ]; then
        (
            cd "$PKGSRC_DIR/$TEST_PKG"
            $makecmd -V "$var" 2>/dev/null || true
        )
    fi
}

expand_pkgsrc_path() {
    path="$1"
    [ -n "$path" ] || return 0
    localbase=$(pkgsrc_make_var LOCALBASE)
    varbase=$(pkgsrc_make_var VARBASE)
    [ -n "$localbase" ] || localbase="${PKGSRC_PREFIX:-/usr/pkg}"
    [ -n "$varbase" ] || varbase="${localbase}/var"
    expanded=$(printf '%s\n' "$path" | sed \
        -e "s#\\\${LOCALBASE}#$localbase#g" \
        -e "s#\\\${VARBASE}#$varbase#g")
    case "$expanded" in
        *'$'*|*'{'*|*'}'*) return 1 ;;
    esac
    printf '%s\n' "$expanded"
}

pkgsrc_pkgdb_dir() {
    if [ -n "$PKGSRC_PKGDBDIR" ]; then
        printf '%s\n' "$PKGSRC_PKGDBDIR"
        return 0
    fi

    raw=$(pkgsrc_make_var PKG_DBDIR)
    if [ -n "$raw" ]; then
        expand_pkgsrc_path "$raw" || true
    fi
}

activate_pkgsrc_pkgdb() {
    pkgdb_dir=$(pkgsrc_pkgdb_dir)
    if [ -n "$pkgdb_dir" ]; then
        PKG_DBDIR="$pkgdb_dir"
        export PKG_DBDIR
        printf 'using pkgdb dir: %s\n' "$PKG_DBDIR"
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

show_make_cmd() {
    makecmd=$(adam_make_cmd)
    version=$(sh -c "$makecmd -V MAKE_VERSION" 2>/dev/null || true)
    if [ -n "$version" ]; then
        printf 'using pkgsrc make: %s (MAKE_VERSION=%s)\n' "$makecmd" "$version"
    else
        printf 'using pkgsrc make: %s\n' "$makecmd"
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
    sucmd=$(pkgsrc_su_cmd) || fail "passwordless doas or sudo is required"
    if [ -n "${PKG_DBDIR:-}" ]; then
        root_exec env PATH="$PATH" PKG_DBDIR="$PKG_DBDIR" SU_CMD="$sucmd" "$ROOT/adam" \
            --pkgsrc "$PKGSRC_DIR" \
            --db "$STATE_DIR/adam-root-pkg.db" \
            --make "$makecmd" \
            --root-cmd none \
            "$@"
    else
        root_exec env PATH="$PATH" SU_CMD="$sucmd" "$ROOT/adam" \
            --pkgsrc "$PKGSRC_DIR" \
            --db "$STATE_DIR/adam-root-pkg.db" \
            --make "$makecmd" \
            --root-cmd none \
            "$@"
    fi
}

run_adam_real() {
    if [ "$ADAM_TEST_BUILD_ROOT" -eq 1 ]; then
        run_adam_as_root "$@"
    else
        run_adam "$@"
    fi
}

pkg_info_has() {
    pkgbase="$1"
    if [ -n "${PKG_DBDIR:-}" ]; then
        PKG_DBDIR="$PKG_DBDIR" pkg_info 2>/dev/null
    else
        pkg_info 2>/dev/null
    fi | awk -v p="$pkgbase" '
        $1 == p || $1 ~ ("^" p "-") { found = 1 }
        END { exit found ? 0 : 1 }
    '
}

assert_pkg_installed() {
    pkgbase="$1"
    pkg_info_has "$pkgbase" || fail "system pkgdb is missing $pkgbase"
}

assert_pkg_absent() {
    pkgbase="$1"
    if pkg_info_has "$pkgbase"; then
        fail "system pkgdb still contains $pkgbase"
    fi
}

assert_adam_installed() {
    pkgbase="$1"
    run_adam_real list --installed > /tmp/adam-list-installed.out
    grep "^$pkgbase	" /tmp/adam-list-installed.out >/dev/null || fail "Adam state is missing $pkgbase"
}

assert_adam_absent() {
    pkgbase="$1"
    run_adam_real list --installed > /tmp/adam-list-installed.out
    if grep "^$pkgbase	" /tmp/adam-list-installed.out >/dev/null; then
        fail "Adam state still contains $pkgbase"
    fi
}

automatic_pkgbases() {
    run_adam_real list --installed | awk -F '\t' '$7 == "1" { print $1 }'
}

installed_pkgbase_for_path() {
    pkgpath="$1"
    run_adam_real list --installed | awk -F '\t' -v p="$pkgpath" '$3 == p { print $1; exit }'
}

run_lifecycle() {
    run_adam_real install "$TEST_PKG"
    ok "real pkgsrc install completed for $TEST_PKG"

    test_pkgbase=$(installed_pkgbase_for_path "$TEST_PKG")
    [ -n "$test_pkgbase" ] || fail "Adam state does not contain installed path $TEST_PKG"
    assert_pkg_installed "$test_pkgbase"
    assert_adam_installed "$test_pkgbase"
    ok "installed package is present in system pkgdb and Adam state"

    automatic_pkgbases > /tmp/adam-auto-before-remove.out
    run_adam_real policy "$TEST_PKG" > /tmp/adam-policy.out
    grep "Installed:" /tmp/adam-policy.out >/dev/null || fail "policy reports installed package"
    ok "policy reports lifecycle package"

    run_adam_real remove "$TEST_PKG"
    assert_pkg_absent "$test_pkgbase"
    assert_adam_absent "$test_pkgbase"
    ok "real pkgsrc remove completed for $TEST_PKG"

    if [ -s /tmp/adam-auto-before-remove.out ]; then
        run_adam_real autoremove
        while IFS= read -r pkgbase; do
            [ -n "$pkgbase" ] || continue
            assert_adam_absent "$pkgbase"
            assert_pkg_absent "$pkgbase"
        done < /tmp/adam-auto-before-remove.out
        ok "real pkgsrc autoremove cleaned Adam-managed automatic dependencies"
    else
        ok "no Adam-managed automatic dependencies to autoremove"
    fi
}

ensure_pkgsrc
mkdir -p "$STATE_DIR"
show_disk_space
bootstrap_pkgsrc
activate_pkgsrc_prefix
activate_pkgsrc_pkgdb
show_make_cmd

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
        run_adam_real build "$TEST_PKG"
        ok "real pkgsrc build completed for $TEST_PKG"
        ;;
    lifecycle)
        run_lifecycle
        ;;
    *)
        fail "unknown mode: $MODE"
        ;;
esac

#!/usr/bin/env bash
# build-wasm.sh — reproducible Zeek WASM build
#
# Prerequisites:
#   - emscripten (emcc, emcmake, emconfigure) in PATH
#   - cmake, ninja, flex, bison, python3, git in PATH
#
# Usage:
#   ./cmake/wasm/build-wasm.sh [--jobs N]
#
# Output:
#   build/zeek-wasm/src/zeek.js  + zeek.wasm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZEEK_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"       # zeek/ source root
WORKSPACE="$(cd "$ZEEK_SRC/.." && pwd)"           # enscripten-zeek/ workspace root

DEPS_DIR="$WORKSPACE/deps"
BUILD_DIR="$WORKSPACE/build"

JOBS="${JOBS:-$(nproc)}"

# Dependency versions
LIBPCAP_VERSION="1.10.5"
OPENSSL_VERSION="3.4.1"

# Colour helpers
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[wasm]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC}   $*"; }
die()   { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
info "Checking prerequisites..."
for cmd in emcc emcmake emconfigure cmake ninja flex bison python3 git; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required tool not found: $cmd"
done
EMCC_VERSION=$(emcc --version 2>&1 | head -1)
info "  $EMCC_VERSION"
ok "Prerequisites OK"

mkdir -p "$DEPS_DIR" "$BUILD_DIR"
export ZEEK_WASM_DEPS_DIR="$DEPS_DIR"

# We do not use any emscripten ports (zlib etc. are built from source), so
# we leave EM_CACHE unset and let emscripten use its system cache
# (/usr/share/emscripten/cache). With FROZEN_CACHE=True the system cache is
# read-only but already contains the required sysroot — which is all we need.

# ---------------------------------------------------------------------------
# Phase 1: libpcap
# ---------------------------------------------------------------------------
LIBPCAP_INSTALL="$DEPS_DIR/libpcap-wasm"

if [ -f "$LIBPCAP_INSTALL/lib/libpcap.a" ]; then
    ok "Phase 1: libpcap already built, skipping."
else
    info "Phase 1: Building libpcap $LIBPCAP_VERSION with emscripten..."

    LIBPCAP_SRC="$DEPS_DIR/libpcap-$LIBPCAP_VERSION"
    LIBPCAP_TARBALL="$DEPS_DIR/libpcap-$LIBPCAP_VERSION.tar.gz"

    if [ ! -f "$LIBPCAP_TARBALL" ]; then
        info "  Downloading libpcap $LIBPCAP_VERSION..."
        curl -fsSL "https://www.tcpdump.org/release/libpcap-$LIBPCAP_VERSION.tar.gz" \
            -o "$LIBPCAP_TARBALL"
    fi

    if [ ! -d "$LIBPCAP_SRC" ]; then
        tar -xzf "$LIBPCAP_TARBALL" -C "$DEPS_DIR"
    fi

    mkdir -p "$LIBPCAP_INSTALL"
    pushd "$LIBPCAP_SRC" >/dev/null

    CFLAGS="-pthread -fwasm-exceptions" emconfigure ./configure \
        --prefix="$LIBPCAP_INSTALL" \
        --disable-shared \
        --disable-usb \
        --disable-bluetooth \
        --disable-dbus \
        --disable-rdma \
        --without-libnl \
        --with-pcap=null \
        --host=wasm32-unknown-emscripten

    emmake make -j"$JOBS"
    emmake make install

    popd >/dev/null
    ok "Phase 1: libpcap built → $LIBPCAP_INSTALL"
fi

# c-ares: built automatically as add_subdirectory(auxil/c-ares) inside Zeek's
# own CMake run. No pre-build step needed. DNS lookups won't work at runtime
# in WASM, but c-ares compiles fine and is only used by DNS_Mgr.cc.

# ---------------------------------------------------------------------------
# Phase 2b: zlib
# ---------------------------------------------------------------------------
# Zeek requires zlib unconditionally (ZIP analyzer, HTTP content decoding,
# pcapng compressed blocks). We build it from source instead of using the
# emscripten port system, which requires write access to the system cache.
# ---------------------------------------------------------------------------
ZLIB_VERSION="1.3.1"
ZLIB_INSTALL="$DEPS_DIR/zlib-wasm"

if [ -f "$ZLIB_INSTALL/lib/libz.a" ]; then
    ok "Phase 2b: zlib already built, skipping."
else
    info "Phase 2b: Building zlib $ZLIB_VERSION with emscripten..."

    ZLIB_SRC="$DEPS_DIR/zlib-$ZLIB_VERSION"
    ZLIB_TARBALL="$DEPS_DIR/zlib-$ZLIB_VERSION.tar.gz"

    if [ ! -f "$ZLIB_TARBALL" ]; then
        info "  Downloading zlib $ZLIB_VERSION..."
        # zlib.net removes old releases; fossils mirror keeps them all.
        curl -fsSL "https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz" \
            -o "$ZLIB_TARBALL"
    fi

    if [ ! -d "$ZLIB_SRC" ]; then
        tar -xzf "$ZLIB_TARBALL" -C "$DEPS_DIR"
    fi

    mkdir -p "$ZLIB_INSTALL"
    pushd "$ZLIB_SRC" >/dev/null

    # zlib's configure is a custom shell script, not autoconf.
    # emconfigure works fine here.
    CFLAGS="-pthread -fwasm-exceptions" emconfigure ./configure \
        --prefix="$ZLIB_INSTALL" \
        --static

    emmake make -j"$JOBS" libz.a
    emmake make install

    popd >/dev/null
    ok "Phase 2b: zlib built → $ZLIB_INSTALL"
fi

# ---------------------------------------------------------------------------
# Phase 3: OpenSSL
# ---------------------------------------------------------------------------
OPENSSL_INSTALL="$DEPS_DIR/openssl-wasm"

if [ -f "$OPENSSL_INSTALL/lib/libssl.a" ]; then
    ok "Phase 3: OpenSSL already built, skipping."
else
    info "Phase 3: Building OpenSSL $OPENSSL_VERSION with emscripten..."

    OPENSSL_SRC="$DEPS_DIR/openssl-$OPENSSL_VERSION"
    OPENSSL_TARBALL="$DEPS_DIR/openssl-$OPENSSL_VERSION.tar.gz"

    if [ ! -f "$OPENSSL_TARBALL" ]; then
        info "  Downloading OpenSSL $OPENSSL_VERSION..."
        curl -fsSL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" \
            -o "$OPENSSL_TARBALL"
    fi

    if [ ! -d "$OPENSSL_SRC" ]; then
        tar -xzf "$OPENSSL_TARBALL" -C "$DEPS_DIR"
    fi

    mkdir -p "$OPENSSL_INSTALL"
    pushd "$OPENSSL_SRC" >/dev/null

    # Use CC=emcc directly rather than emconfigure: emconfigure prepends the
    # emscripten path to the CC variable which OpenSSL then double-expands,
    # producing a broken path like /usr/share/emscripten/em/usr/.../emcc.
    # Setting CC=emcc before ./Configure avoids this.
    CC="emcc -pthread -fwasm-exceptions" CXX="em++ -pthread -fwasm-exceptions" AR=emar RANLIB=emranlib ./Configure linux-generic32 \
        --prefix="$OPENSSL_INSTALL" \
        --openssldir="$OPENSSL_INSTALL/ssl" \
        no-asm \
        no-shared \
        no-afalgeng \
        no-hw \
        no-threads \
        no-dso \
        no-engine \
        no-tests

    # Generate headers first (opensslv.h etc. are created from .h.in templates
    # via Perl — this must complete before parallel compilation starts or the
    # compiler will fail with "opensslv.h not found").
    make build_generated

    emmake make -j"$JOBS" libssl.a libcrypto.a
    emmake make install_dev   # headers + libs only, skip binaries

    popd >/dev/null
    ok "Phase 3: OpenSSL built → $OPENSSL_INSTALL"
fi

# ---------------------------------------------------------------------------
# Phase 4+5: Zeek
# ---------------------------------------------------------------------------
ZEEK_BUILD="$BUILD_DIR/zeek-wasm"

info "Phase 5: Configuring Zeek with emscripten..."

emcmake cmake -S "$ZEEK_SRC" \
    -B "$ZEEK_BUILD" \
    -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/emscripten-toolchain.cmake" \
    -DZEEK_WASM_DEPS_DIR="$DEPS_DIR"

# The bif directory isn't created by CMake's install rules before the first
# build; create it now so cmake -E copy doesn't fail.
mkdir -p "$ZEEK_BUILD/scripts/base/bif"

info "Phase 5: Building Zeek (this will take a while)..."
cmake --build "$ZEEK_BUILD" -j"$JOBS" --target zeek_exe

# ---------------------------------------------------------------------------
# Phase 6: Patch zeek.js — wrap ___funcs_on_exit() in try-catch
# ---------------------------------------------------------------------------
# exitRuntime() calls __funcs_on_exit() which runs C++ atexit/destructor
# handlers.  One of those handlers (from OpenSSL or prometheus-cpp) has a
# null or type-mismatched function pointer in the WASM indirect call table,
# causing a RuntimeError.  Log files are fully written to the virtual FS
# before exit() is called, so destructors don't need to succeed.
# We wrap just that one call in a try-catch so onExit still fires normally.
ZEEK_JS="$ZEEK_BUILD/src/zeek.js"
python3 - "$ZEEK_JS" << 'PYEOF'
import sys
path = sys.argv[1]
old = '___funcs_on_exit();'
new = 'try{___funcs_on_exit();}catch(e){console.warn("[zeek] exitRuntime error (ignored):",e);}'
code = open(path).read()
if old not in code:
    print(f"[patch] WARNING: '{old}' not found in zeek.js — patch not applied", flush=True)
    sys.exit(0)
open(path, 'w').write(code.replace(old, new, 1))
print(f"[patch] Patched exitRuntime in {path}", flush=True)
PYEOF

cp "$SCRIPT_DIR/test.html" "$ZEEK_BUILD/src/test.html"
ok "Phase 6: zeek.js patched and test.html copied → $ZEEK_BUILD/src/"

ok "Build complete!"
echo ""
echo "  WASM:    $ZEEK_BUILD/src/zeek.wasm"
echo "  JS glue: $ZEEK_BUILD/src/zeek.js"
echo "  Data:    $ZEEK_BUILD/src/zeek.data  (preloaded Zeek scripts)"
echo "  Test:    $ZEEK_BUILD/src/test.html"
echo ""
echo "To test in a browser (all four files must be served together):"
echo "  cd $ZEEK_BUILD/src && python3 $SCRIPT_DIR/serve.py"
echo "  Open http://localhost:8080/test.html"
echo ""
echo "  NOTE: pthreads require SharedArrayBuffer which requires COOP/COEP headers."
echo "  serve.py sets these automatically. plain 'python3 -m http.server' will NOT work."

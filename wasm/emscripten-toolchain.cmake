# Emscripten CMake toolchain file for Zeek WASM build.
# Used by build-wasm.sh via:  emcmake cmake -DCMAKE_TOOLCHAIN_FILE=<this file> ...
#
# Problem: passing -DCMAKE_TOOLCHAIN_FILE=<ours> to emcmake overrides the
# emscripten toolchain that emcmake would normally inject, so CMake falls back
# to the native compiler.  Fix: locate and chain into the official
# Emscripten.cmake first, then layer our Zeek-specific settings on top.

# ---------------------------------------------------------------------------
# 1. Chain into the official Emscripten toolchain
# ---------------------------------------------------------------------------

# Build a list of candidate paths for Emscripten.cmake and pick the first one
# that exists.  We need to handle several installation layouts:
#   - emsdk: $EMSCRIPTEN points to the SDK root directly
#   - Debian/Ubuntu package: emcc → /usr/bin/emcc (symlink to
#     /usr/share/emscripten/wrapper), SDK root = /usr/share/emscripten
#   - Other distros: emcc may be a real binary inside the SDK tree

set(_emscripten_cmake_candidates "")

# 1a. $EMSCRIPTEN env var (set by emsdk_env.sh)
if (DEFINED ENV{EMSCRIPTEN})
    list(APPEND _emscripten_cmake_candidates
        "$ENV{EMSCRIPTEN}/cmake/Modules/Platform/Emscripten.cmake")
endif ()

# 1b. Derive from the resolved realpath of emcc
find_program(_emcc_path emcc)
if (_emcc_path)
    get_filename_component(_emcc_real "${_emcc_path}" REALPATH)
    get_filename_component(_emcc_dir  "${_emcc_real}" DIRECTORY)
    list(APPEND _emscripten_cmake_candidates
        # SDK root IS the directory containing the emcc script
        "${_emcc_dir}/cmake/Modules/Platform/Emscripten.cmake"
        # SDK root is one level up (e.g. sdk/upstream/emscripten/emcc → sdk/upstream/emscripten)
        "${_emcc_dir}/../cmake/Modules/Platform/Emscripten.cmake"
    )
endif ()

# 1c. Well-known system-package location (Debian/Ubuntu: emscripten pkg)
list(APPEND _emscripten_cmake_candidates
    "/usr/share/emscripten/cmake/Modules/Platform/Emscripten.cmake")

foreach(_candidate IN LISTS _emscripten_cmake_candidates)
    if (EXISTS "${_candidate}")
        set(_emscripten_cmake "${_candidate}")
        break()
    endif ()
endforeach()

if (NOT DEFINED _emscripten_cmake)
    message(FATAL_ERROR
        "Could not find Emscripten.cmake. "
        "Set the EMSCRIPTEN environment variable to your Emscripten SDK root, "
        "or install the emscripten system package.")
endif ()

include("${_emscripten_cmake}")

# ---------------------------------------------------------------------------
# 1b. Relax find_package root-path restrictions
# ---------------------------------------------------------------------------
# Emscripten.cmake sets CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY, which causes
# find_package(CONFIG PATHS <dir>) to silently ignore paths outside the
# emscripten sysroot (e.g. Broker's zeek-bundle prefix for prometheus-cpp).
# Setting BOTH lets CMake search both the sysroot AND explicitly given paths.
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH CACHE STRING "" FORCE)

# ---------------------------------------------------------------------------
# 2. Zeek feature flags — disable anything that needs a real OS
# ---------------------------------------------------------------------------
set(DISABLE_SPICY                    ON  CACHE BOOL "" FORCE)
set(DISABLE_BROKER                   ON  CACHE BOOL "" FORCE)
set(DISABLE_PYTHON_BINDINGS          ON  CACHE BOOL "" FORCE)
set(ENABLE_CLUSTER_BACKEND_ZEROMQ    OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS       OFF CACHE BOOL "" FORCE)
set(ENABLE_JEMALLOC         OFF CACHE BOOL "" FORCE)
set(ENABLE_PERFTOOLS        OFF CACHE BOOL "" FORCE)
set(INSTALL_ZEEKCTL         OFF CACHE BOOL "" FORCE)
set(INSTALL_AUX_TOOLS       OFF CACHE BOOL "" FORCE)
set(INSTALL_BTEST           OFF CACHE BOOL "" FORCE)
set(INSTALL_BTEST_PCAPS     OFF CACHE BOOL "" FORCE)
set(INSTALL_ZEEK_CLIENT     OFF CACHE BOOL "" FORCE)
set(INSTALL_ZKG             OFF CACHE BOOL "" FORCE)
set(ZEEK_ENABLE_FUZZERS     OFF CACHE BOOL "" FORCE)
set(ENABLE_ZEEK_UNIT_TESTS  OFF CACHE BOOL "" FORCE)

# ---------------------------------------------------------------------------
# 3. Paths to emscripten-compiled dependencies
# ---------------------------------------------------------------------------
# Prefer the cmake variable passed via -DZEEK_WASM_DEPS_DIR=..., then the
# environment variable exported by build-wasm.sh, then a sensible default
# relative to the workspace root (two levels up from the build dir).
if (DEFINED ZEEK_WASM_DEPS_DIR)
    set(_deps "${ZEEK_WASM_DEPS_DIR}")
elseif (DEFINED ENV{ZEEK_WASM_DEPS_DIR})
    set(_deps "$ENV{ZEEK_WASM_DEPS_DIR}")
else ()
    # build dir is <workspace>/build/zeek-wasm, so ../../deps = <workspace>/deps
    get_filename_component(_deps "${CMAKE_BINARY_DIR}/../../deps" ABSOLUTE)
endif ()

# Set the root dirs so Zeek's FindXxx.cmake scripts pick them up, AND pre-set
# the leaf variables (INCLUDE_DIR / LIBRARY) so that find_path/find_library
# skip their search entirely.  This is necessary because Emscripten.cmake sets
# CMAKE_FIND_ROOT_PATH_MODE_{INCLUDE,LIBRARY}=ONLY, which causes find_path and
# find_library to ignore HINTS pointing outside the emscripten sysroot.

set(PCAP_ROOT_DIR    "${_deps}/libpcap-wasm"          CACHE PATH     "" FORCE)
set(PCAP_INCLUDE_DIR "${_deps}/libpcap-wasm/include"  CACHE PATH     "" FORCE)
set(PCAP_LIBRARY     "${_deps}/libpcap-wasm/lib/libpcap.a" CACHE FILEPATH "" FORCE)

set(OPENSSL_ROOT_DIR "${_deps}/openssl-wasm"          CACHE PATH "" FORCE)
set(OPENSSL_INCLUDE_DIR "${_deps}/openssl-wasm/include" CACHE PATH "" FORCE)
set(OPENSSL_SSL_LIBRARY     "${_deps}/openssl-wasm/lib/libssl.a"    CACHE FILEPATH "" FORCE)
set(OPENSSL_CRYPTO_LIBRARY  "${_deps}/openssl-wasm/lib/libcrypto.a" CACHE FILEPATH "" FORCE)

set(ZLIB_ROOT        "${_deps}/zlib-wasm"             CACHE PATH     "" FORCE)
set(ZLIB_INCLUDE_DIR "${_deps}/zlib-wasm/include"     CACHE PATH     "" FORCE)
set(ZLIB_LIBRARY     "${_deps}/zlib-wasm/lib/libz.a"  CACHE FILEPATH "" FORCE)

# c-ares: built automatically as add_subdirectory(auxil/c-ares) inside Zeek's
# own cmake run — no pre-built path needed.

# ---------------------------------------------------------------------------
# 4. Emscripten linker flags
# ---------------------------------------------------------------------------
# FORCE_FILESYSTEM: required for pcap file I/O via the virtual FS.
# ALLOW_MEMORY_GROWTH: lets the heap expand as Zeek loads scripts.
# INVOKE_RUN=0: don't call main() automatically; JS wrapper controls startup.
set(_wasm_link_flags
    "-sWASM=1"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sINITIAL_MEMORY=67108864"
)
# FORCE_FILESYSTEM and EXPORTED_RUNTIME_METHODS / INVOKE_RUN are applied
# only to the zeek_exe target (via target_link_options in src/CMakeLists.txt).
# Build tools (bifcl, binpac, gen-zam) get -sNODERAWFS=1 instead so they
# write their generated files to the real host filesystem under Node.js.
list(JOIN _wasm_link_flags " " _wasm_link_flags_str)
set(CMAKE_EXE_LINKER_FLAGS    "${_wasm_link_flags_str}" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${_wasm_link_flags_str}" CACHE STRING "" FORCE)

# ---------------------------------------------------------------------------
# 5. Emscripten stub headers
# ---------------------------------------------------------------------------
# Some POSIX headers missing from emscripten's sysroot are stubbed here:
#   sys/prctl.h — used by libkqueue posix backend (thread naming, no-op)
#   fts.h       — used by zeekygen doc generator (never called in WASM)
get_filename_component(_wasm_stubs_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
set(_wasm_stubs "${_wasm_stubs_dir}/emscripten-stubs")
include_directories(SYSTEM "${_wasm_stubs}")

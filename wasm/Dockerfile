# Dockerfile for reproducible Zeek WASM build.
#
# Usage:
#   docker build -f cmake/wasm/Dockerfile -t zeek-wasm .
#   docker run --rm -v "$(pwd)/output:/out" zeek-wasm \
#       cp /zeek/build/zeek-wasm/src/zeek.js /zeek/build/zeek-wasm/src/zeek.wasm /out/
#
# The image pins the emscripten version for a fully reproducible build.

FROM emscripten/emsdk:3.1.69

RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        ninja-build \
        flex \
        bison \
        python3 \
        python3-dev \
        git \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /zeek-src
COPY . .

RUN cmake/wasm/build-wasm.sh

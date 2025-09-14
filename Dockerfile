# syntax=docker/dockerfile:1-labs

# Build environment
FROM ubuntu:22.04 AS build-env

RUN apt-get update && apt-get install -y \
    build-essential \
    make \
    git \
    wget \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    flex \
    bison \
    gperf \
    libffi-dev \
    libssl-dev \
    dfu-util \
    libusb-1.0-0 \
    pkg-config \
    ca-certificates \
    gpg \
    autoconf \
    autoconf-archive \
    automake \
    libtool \
    && rm -rf /var/lib/apt/lists/*

## Add kitware repository (needed for CMake v4)
RUN ( \
    test -f /usr/share/doc/kitware-archive-keyring/copyright || \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null \
    )  && \
    echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ jammy main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    apt-get update && \
    ( \
    test -f /usr/share/doc/kitware-archive-keyring/copyright || \
    rm /usr/share/keyrings/kitware-archive-keyring.gpg \
    ) && \
    apt-get install kitware-archive-keyring

## Install CMake v4
RUN apt-get update && apt-get install -y cmake


## Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /workspace

# ESP-IDF
FROM build-env AS esp-idf

COPY taskfile.idf.yml esp-export.sh esp-idf-path.sh ./

ENV IDF_PATH=/workspace/.esp-idf
RUN task --taskfile ./taskfile.idf.yml ensure-available

# C toolchain and dependencies
FROM esp-idf AS c-dependencies

RUN apt-get update && apt-get install -y \
    ninja-build \
    ccache \
    libffi-dev \
    libssl-dev \
    dfu-util \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/c

COPY ./c/CMakeLists.txt ./c/toolchain.cmake ./
COPY ./c/dependencies/toolchain.cmake ./dependencies/

RUN mkdir -p build && \
    cd build && \
    cmake .. && \
    make toolchain

COPY ./c/dependencies/* ./dependencies
COPY ./c/dependencies.cmake .
RUN cd build && \
    cmake .. && \
    make dependencies

# C build os
FROM c-dependencies AS c-build-os

COPY ./c/1-blinky ./1-blinky/
COPY ./c/2-motor ./2-motor/
COPY ./c/3-pid ./3-pid/
COPY ./c/targets.cmake ./c/taskfile.c.yml ./
COPY ./taskfile.var.yml ./..

ENV TASK_TEMP_DIR=../.task
ARG REVOLUTION_THRESHOLD_CLOSE
ARG REVOLUTION_THRESHOLD_FAR
RUN task --taskfile ./taskfile.c.yml --dir . build-every-profile-os

# C build bm
FROM c-dependencies AS c-build-bm

COPY ./c/1-blinky-bm ./1-blinky-bm/
COPY ./c/2-motor-bm ./2-motor-bm/
COPY ./c/3-pid-bm ./3-pid-bm/
COPY ./c/taskfile.c.yml ./
COPY ./taskfile.var.yml ./..

ENV TASK_TEMP_DIR=../.task
ARG REVOLUTION_THRESHOLD_CLOSE
ARG REVOLUTION_THRESHOLD_FAR
RUN --mount=type=secret,id=WIFI_SSID,env=WIFI_SSID \
    --mount=type=secret,id=WIFI_PASS,env=WIFI_PASS \
    task --taskfile ./taskfile.c.yml --dir . build-every-profile-bm

# Zig toolchain and dependencies
FROM esp-idf AS zig-dependencies

RUN curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash
ENV PATH="/root/.zvm/bin:/root/.zvm/self:$PATH"
RUN zvm install 0.13.0
RUN zvm install 0.14.0

WORKDIR /workspace/zig

COPY ./zig/1-blinky/build.zig.zon ./1-blinky/
RUN touch 1-blinky/build.zig
RUN cd ./1-blinky && zvm run 0.13.0 build --fetch

COPY ./zig/2-motor/build.zig.zon ./2-motor/
RUN touch 2-motor/build.zig
RUN cd ./2-motor && zvm run 0.13.0 build --fetch

COPY ./zig/3-pid/build.zig.zon ./3-pid/
RUN touch 3-pid/build.zig
RUN cd ./3-pid && zvm run 0.13.0 build --fetch

COPY ./zig/1-blinky-bm/build.zig.zon ./1-blinky-bm/
RUN touch 1-blinky-bm/build.zig
RUN cd ./1-blinky-bm && zvm run 0.14.0 build --fetch

COPY ./zig/2-motor-bm/build.zig.zon ./2-motor-bm/
RUN touch 2-motor-bm/build.zig
RUN cd ./2-motor-bm && zvm run 0.14.0 build --fetch

COPY ./zig/3-pid-bm/build.zig.zon ./3-pid-bm/
RUN touch 3-pid-bm/build.zig
RUN cd ./3-pid-bm && zvm run 0.14.0 build --fetch

# Zig build os
FROM zig-dependencies AS zig-build-os

# Works with newer versions as well
RUN ln -f /usr/bin/aclocal /usr/bin/aclocal-1.17
RUN ln -f /usr/bin/automake /usr/bin/automake-1.17

RUN apt-get update && apt-get install -y \
    gcc-arm-linux-gnueabihf \
    && rm -rf /var/lib/apt/lists/*
ENV CC=arm-linux-gnueabihf-gcc      \
    CXX=arm-linux-gnueabihf-g++     \
    AR=arm-linux-gnueabihf-ar       \
    STRIP=arm-linux-gnueabihf-strip

COPY ./zig/1-blinky ./1-blinky/
COPY ./zig/2-motor ./2-motor/
COPY ./zig/3-pid ./3-pid/
COPY ./zig/taskfile.zig.yml ./
COPY ./taskfile.var.yml ./..

ENV TASK_TEMP_DIR=../.task
ARG REVOLUTION_THRESHOLD_CLOSE
ARG REVOLUTION_THRESHOLD_FAR
RUN task --taskfile ./taskfile.zig.yml --dir . build-every-profile-os

# Zig build bm
FROM zig-dependencies AS zig-build-bm

COPY ./zig/idf-repeat.sh .

COPY ./zig/1-blinky-bm ./1-blinky-bm/
COPY ./zig/2-motor-bm ./2-motor-bm/
COPY ./zig/3-pid-bm ./3-pid-bm/
COPY ./zig/taskfile.zig.yml ./
COPY ./taskfile.var.yml ./..

ENV TASK_TEMP_DIR=../.task
ARG REVOLUTION_THRESHOLD_CLOSE
ARG REVOLUTION_THRESHOLD_FAR
RUN --mount=type=secret,id=WIFI_SSID,env=WIFI_SSID \
    --mount=type=secret,id=WIFI_PASS,env=WIFI_PASS \
    task --taskfile ./taskfile.zig.yml --dir . build-every-profile-bm

# Rust toolchain
FROM esp-idf AS rust-toolchain

RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:$PATH"
RUN rustup toolchain install nightly-2025-08-25
RUN rustup default nightly-2025-08-25

WORKDIR /workspace/rust

# Rust build os
FROM rust-toolchain AS rust-build-os

RUN rustup target add arm-unknown-linux-gnueabihf

RUN wget -q https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/Bookworm/GCC%2014.2.0/Raspberry%20Pi%201%2C%20Zero/cross-gcc-14.2.0-pi_0-1.tar.gz/download -O rpi-toolchain.tar.gz && \
    tar -xzf rpi-toolchain.tar.gz -C /opt && \
    rm rpi-toolchain.tar.gz
ENV PATH="/opt/cross-pi-gcc-14.2.0-0/bin:${PATH}"

RUN mkdir -p ~/.cargo && echo '[target.arm-unknown-linux-gnueabihf]\nlinker = "arm-linux-gnueabihf-gcc"' > ~/.cargo/config.toml

RUN mkdir -p 1-blinky/src 2-motor/src 3-pid/src
RUN echo "fn main() {}" | tee \
    1-blinky/src/main.rs \
    2-motor/src/main.rs \
    3-pid/src/main.rs

COPY ./rust/Cargo.toml ./rust/Cargo.lock ./

# TODO: Fix dependency build for rust. It works, but invoking cargo the second
# time for the actual build doesn't produce a different binary.
#
# COPY ./rust/1-blinky/Cargo.toml ./1-blinky/
# COPY ./rust/2-motor/Cargo.toml ./2-motor/
# COPY ./rust/3-pid/Cargo.toml ./3-pid/
#
# RUN cargo build --package blinky --profile=fast \
#     --target=arm-unknown-linux-gnueabihf
# RUN RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --package blinky --profile=small \
#     --target=arm-unknown-linux-gnueabihf
# RUN cargo build --package motor --profile=fast \
#     --target=arm-unknown-linux-gnueabihf  
# RUN RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --package motor --profile=small \
#     --target=arm-unknown-linux-gnueabihf  
# RUN cargo build --package pid --profile=fast \
#     --target=arm-unknown-linux-gnueabihf
# RUN RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --package pid --profile=small \
#     --target=arm-unknown-linux-gnueabihf

COPY ./rust/1-blinky ./1-blinky/
COPY ./rust/2-motor ./2-motor/
COPY ./rust/3-pid ./3-pid/
COPY ./rust/taskfile.rust.yml ./
COPY ./taskfile.var.yml ./..

ENV TASK_TEMP_DIR=../.task
ENV RUST_BUILD_TOOL=cargo
ARG REVOLUTION_THRESHOLD_CLOSE
ARG REVOLUTION_THRESHOLD_FAR
RUN task --taskfile ./taskfile.rust.yml --dir . build-every-profile-os

# Rust build bm
FROM rust-toolchain AS rust-build-bm

RUN apt-get update && apt-get install -y \
    libclang-dev \
    libudev-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cargo install espup --locked --version 0.14.1
RUN espup install
RUN cargo install ldproxy --locked --version 0.3.4
RUN cargo install espflash --locked --version 3.3.0

RUN mkdir -p 0-tune-bm/src 1-blinky-bm/src 2-motor-bm/src 3-pid-bm/src
RUN echo "fn main() {}" | tee \
    0-tune-bm/src/main.rs \
    1-blinky-bm/src/main.rs \
    2-motor-bm/src/main.rs \
    3-pid-bm/src/main.rs

COPY --exclude=src ./rust/0-tune-bm ./0-tune-bm/
RUN cd 0-tune-bm && cargo build --profile=fast
RUN cd 0-tune-bm && RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --profile=small
COPY --exclude=src ./rust/1-blinky-bm ./1-blinky-bm/
RUN cd 1-blinky-bm && cargo build --profile=fast
RUN cd 1-blinky-bm && RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --profile=small
COPY --exclude=src ./rust/2-motor-bm ./2-motor-bm/
RUN cd 2-motor-bm && cargo build --profile=fast
RUN cd 2-motor-bm && RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --profile=small
COPY --exclude=src ./rust/3-pid-bm ./3-pid-bm/
RUN cd 3-pid-bm && cargo build --profile=fast
RUN cd 3-pid-bm && RUSTFLAGS="-Zfmt-debug=none -Zlocation-detail=none" cargo build --profile=small

COPY ./rust/1-blinky-bm ./1-blinky-bm/
COPY ./rust/2-motor-bm ./2-motor-bm/
COPY ./rust/3-pid-bm ./3-pid-bm/
COPY ./rust/0-tune-bm ./0-tune-bm/
COPY ./rust/taskfile.rust.yml ./
COPY ./taskfile.var.yml ./..

ENV TASK_TEMP_DIR=../.task
ARG REVOLUTION_THRESHOLD_CLOSE
ARG REVOLUTION_THRESHOLD_FAR
RUN --mount=type=secret,id=WIFI_SSID,env=WIFI_SSID \
    --mount=type=secret,id=WIFI_PASS,env=WIFI_PASS \
    task --taskfile ./taskfile.rust.yml --dir . build-every-profile-bm

# Copy to bound directory (see docker-compose)
FROM ubuntu:22.04 AS runtime

COPY --from=c-build-os /workspace/artifacts/ /artifacts/
COPY --from=c-build-bm /workspace/artifacts/ /artifacts/

COPY --from=zig-build-os /workspace/artifacts/ /artifacts/
COPY --from=zig-build-bm /workspace/artifacts/ /artifacts/

COPY --from=rust-build-os /workspace/artifacts/ /artifacts/
COPY --from=rust-build-bm /workspace/artifacts/ /artifacts/

CMD mkdir -p /artifacts-bind && cp -r /artifacts/* /artifacts-bind

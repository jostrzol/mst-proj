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

ENV TASK_TEMP_DIR=../.task
RUN task --taskfile ./taskfile.c.yml --dir . build-every-profile-os

# C build bm
FROM c-dependencies AS c-build-bm

COPY ./c/1-blinky-bm ./1-blinky-bm/
COPY ./c/2-motor-bm ./2-motor-bm/
COPY ./c/3-pid-bm ./3-pid-bm/
COPY ./c/taskfile.c.yml ./

ENV TASK_TEMP_DIR=../.task
RUN task --taskfile ./taskfile.c.yml --dir . build-every-profile-bm

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

COPY ./zig/1-blinky ./1-blinky/
COPY ./zig/2-motor ./2-motor/
COPY ./zig/3-pid ./3-pid/
COPY ./zig/taskfile.zig.yml ./

ENV TASK_TEMP_DIR=../.task
RUN task --taskfile ./taskfile.zig.yml --dir . build-every-profile-os

# Zig build bm
FROM zig-dependencies AS zig-build-bm

COPY ./zig/idf-repeat.sh .

COPY ./zig/1-blinky-bm ./1-blinky-bm/
COPY ./zig/2-motor-bm ./2-motor-bm/
COPY ./zig/3-pid-bm ./3-pid-bm/
COPY ./zig/taskfile.zig.yml ./

ENV TASK_TEMP_DIR=../.task
RUN task --taskfile ./taskfile.zig.yml --dir . build-every-profile-bm

# Copy to bound directory (see docker-compose)
FROM ubuntu:22.04 AS runtime

COPY --from=c-build-os /workspace/artifacts/ /artifacts/
COPY --from=c-build-bm /workspace/artifacts/ /artifacts/

COPY --from=zig-build-os /workspace/artifacts/ /artifacts/
COPY --from=zig-build-bm /workspace/artifacts/ /artifacts/

WORKDIR /

CMD cp -r /artifacts/* /artifacts-bind

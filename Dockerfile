# ==============================================================================
# Build environment
# ==============================================================================
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

# Add kitware repository
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

# Install CMake v4
RUN apt-get update && apt-get install -y cmake


# Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /workspace

# ==============================================================================
# ESP-IDF
# ==============================================================================
FROM build-env AS esp-idf

COPY taskfile.idf.yml esp-export.sh esp-idf-path.sh ./

ENV IDF_PATH=/workspace/.esp-idf
RUN task --taskfile ./taskfile.idf.yml ensure-available

# ==============================================================================
# C toolchain and dependencies
# ==============================================================================
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

# ==============================================================================
# OS binaries  
# ==============================================================================
FROM c-dependencies AS build-os

COPY ./c/1-blinky ./1-blinky/
COPY ./c/2-motor ./2-motor/
COPY ./c/3-pid ./3-pid/
COPY ./c/targets.cmake ./c/taskfile.c.yml ./

ENV TASK_TEMP_DIR=../.task
RUN task --taskfile ./taskfile.c.yml --dir . build-every-profile-os

# ==============================================================================
# BM binaries
# ==============================================================================  
FROM c-dependencies AS build-bm

COPY ./c/1-blinky-bm ./1-blinky-bm/
COPY ./c/2-motor-bm ./2-motor-bm/
COPY ./c/3-pid-bm ./3-pid-bm/
COPY ./c/taskfile.c.yml ./

ENV TASK_TEMP_DIR=../.task
RUN task --taskfile ./taskfile.c.yml --dir . build-every-profile-bm

# ==============================================================================
# Copy to binded directory
# ==============================================================================
FROM ubuntu:22.04 AS runtime

RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/*

COPY --from=build-os /workspace/artifacts/ /artifacts/
COPY --from=build-bm /workspace/artifacts/ /artifacts/

WORKDIR /

CMD cp -r /artifacts/* /artifacts-bind

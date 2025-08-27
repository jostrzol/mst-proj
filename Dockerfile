# ==============================================================================
# Build environment
# ==============================================================================
FROM ubuntu:22.04 AS build-env


# Install system dependencies
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

# Set working directory
WORKDIR /workspace

# ==============================================================================
# ESP-IDF
# ==============================================================================
FROM build-env AS esp-idf

COPY taskfile.idf.yml esp-export.sh esp-idf-path.sh ./

# Setup ESP-IDF for bare-metal builds
ENV IDF_PATH=/workspace/.esp-idf
RUN task --taskfile ./taskfile.idf.yml ensure-available

# ==============================================================================
# C toolchain and dependencies
# ==============================================================================
FROM esp-idf AS c-dependencies

WORKDIR /workspace/c

# Setup ARM cross-compilation toolchain using CMake target
COPY ./c/CMakeLists.txt ./c/toolchain.cmake ./
COPY ./c/dependencies/toolchain.cmake ./dependencies/

RUN mkdir -p build && \
    cd build && \
    cmake .. && \
    make toolchain

# Verify toolchain was downloaded and extracted
RUN ls -la build/cross-pi-gcc-*-0/bin/arm-linux-gnueabihf-gcc || \
    (echo "ARM toolchain not properly setup" && exit 1)

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
# Build BM binaries using taskfile for fast and small profiles
RUN cd .. && task --taskfile ./taskfile.idf.yml ensure-available
RUN ls -la ..; task --taskfile ./taskfile.c.yml --dir . build-every-profile-bm

# ==============================================================================
# Stage 5: Combine and Create Final Runtime Image
# ==============================================================================
FROM ubuntu:22.04 AS runtime

# Copy OS binaries from build-os stage
COPY --from=build-os /workspace/artifacts/ /artifacts/

# Copy BM binaries from build-bm stage (merge with OS artifacts)
COPY --from=build-bm /workspace/artifacts/ /artifacts/

# Set working directory
WORKDIR /artifacts

# Default command shows available binaries
CMD ["sh", "-c", "echo 'Available C binaries:' && echo 'OS binaries:' && find . -name '*-c' -not -name '*-bm-*' -type f | sort && echo 'BM binaries (.bin):' && find . -name '*-bm-c' -type f | sort && echo 'BM binaries (.elf):' && find . -name '*-bm-c.elf' -type f | sort"]

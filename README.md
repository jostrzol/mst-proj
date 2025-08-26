# Master thesis project

## Requirements

- [`git`](https://git-scm.com/)
- [`task`](https://github.com/go-task/task)
- [`uv`](https://github.com/astral-sh/uv)
- [`rustup`](https://github.com/rust-lang/rustup)
- [`zvm`](https://github.com/tristanisham/zvm)
- [`cmake`](https://github.com/Kitware/CMake)
- [`npm`](https://www.npmjs.com/)
- esp-idf requirements:
  - [`python3`](https://www.python.org/)
  - [`ldproxy`](https://github.com/esp-rs/embuild/tree/master/ldproxy) (`cargo
install ldpoxy --locked`)
  - rest specified [on the espressif
    website](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html#step-1-install-prerequisites).

## Building

```sh
task build
```

All binary artifacts are then placed in the `./artifacts/` directory.

## Running

Regardless of platform, before running the code you must:

1. Build a circuit using one of the provided schematics from
   [](./docs/circuits).
2. Ensure that the hardware is correctly configured (see #Configuration).

### Raspberry Pi

1. Copy selected artifact to Raspberry Pi's SD card.
2. SSH into the board.

   ```sh
   ssh raspberrypi.local
   ```

3. Run the selected artifact.

### ESP

1. Attach the ESP using a cable to the computer.
2. Run

   ```sh
   task <language>:run-bm PROJECT=<project>
   ```

   e.g.

   ```sh
   task c:run-bm PROJECT=1-blinky-bm
   ```

   to run the C implementation of `1-blinky-bm`.

## Benchmarking

1. Build a circuit using one of the provided schematics from
   [](./docs/circuits).
2. Ensure that the hardware is correctly configured (see #Configuration).
3. Make sure the connection to the device works:
   - (Raspberry Pi) Ensure that Raspberry Pi is reachable at `raspberrypi.local`.
   - (ESP) Ensure that ESP is plugged into an USB port of the computer.
4. Run:

   ```sh
   task bench:<project>
   ```

   e.g.

   ```sh
   task bench:1-blinky-os
   ```

The results are then written to the `./analyze/out/perf/` directory.

## Configuration

Configuration is done through a `.env` file in the root of the repository. It
can be created using the defaults: `cp .default.env .env`.

### ESP configuration

- `WIFI_SSID` -- SSID of WiFi network that ESP programs can connect to.
  Required to run the `3-pid-bm` project.
- `WIFI_PASS` -- password of WiFi network that ESP programs can connect to.
  Required to run the `3-pid-bm` project.
- `ESPFLASH_PORT` -- USB device used to flash ESP programs. If left empty,
  `espflash` will find it automatically (slower).
- `ESPFLASH_BAUD=115200` -- baud rate for flashing ESP programs. If left empty,
  `espflash` will pick the safest (slowest) possible option.

### Raspberry Pi configuration

Raspberry Pi must configured directly in its operating system. Ensure the
Raspberry Pi peripherals and modules are correctly configured:

- GPIO,
- I2C,
- Hardware PWM,
- mDNS server with address: 'raspberrypi.local',
- WiFi.

For help, refer to [Raspberry Pi documentation](https://www.raspberrypi.com/documentation/).

### Benchmarking configuration

- `USB_VENDOR` -- ESP USB port vendor identifier, on how
  to get this. Required for benchmarking on ESP.
- `USB_PRODUCT` -- ESP USB port product identifier. Required for benchmarking
  on ESP.

See [esp-rs
documentation](https://docs.esp-rs.org/std-training/02_1_hardware.html) for
information on how to set these values.

### Miscellaneous configuration

- `LOG_LEVEL=INFO` -- log level (only for zig programs)

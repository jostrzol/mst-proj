mod c
mod rust
mod zig
mod server

set unstable
set dotenv-load

languages := "c zig rust"
thesis_dir := "../thesis"

build_profile := env("BUILD_PROFILE", "")
export SDKCONFIG_DEFAULTS := if build_profile == "SMALL" {
  "sdkconfig.defaults;sdkconfig.defaults-small"
} else if build_profile == "FAST" {
  "sdkconfig.defaults;sdkconfig.defaults-fast"
} else if build_profile == "DEBUG" {
  "sdkconfig.defaults"
} else if build_profile == "" {
  "sdkconfig.defaults"
} else {
  error("Invalid build profile: " + build_profile)
}

export SDKCONFIG := if build_profile == "SMALL" {
  "sdkconfig.small"
} else if build_profile == "FAST" {
  "sdkconfig.fast"
} else {
  "sdkconfig"
}

build-every-profile:
  BUILD_PROFILE=SMALL just build \
  && BUILD_PROFILE=FAST just build \
  && BUILD_PROFILE=DEBUG just zig::pid-build

build:
  just rust::build \
  & just c::build \
  & just zig::build \
  & wait

build-bm:
  just rust::build-bm \
  & just c::build-bm \
  & just zig::build-bm \
  & wait

build-os:
  just rust::build-os \
  & just c::build-os \
  & just zig::build-os \
  & wait

clean:
  just rust::clean
  just c::clean
  just zig::clean
  

watch-and-serve:
  just artifacts-server \
  & just watch \
  & wait

watch:
  just rust::watch \
  & just c::watch \
  & just zig::watch \
  & wait

artifacts-server:
  python3 -m http.server -d ./artifacts/

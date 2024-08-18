mod c
mod rust
mod zig

build:
  just --unstable rust::build-all \
  & just --unstable c::build-all \
  & just --unstable zig::build-all

watch-and-serve:
  just --unstable artifacts-server & just --unstable watch

watch:
  just --unstable rust::watch-all \
  & just --unstable c::watch-all \
  & just --unstable zig::watch-all

artifacts-server:
  python3 -m http.server -d ./artifacts/

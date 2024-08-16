mod c
mod rust

build:
  just --unstable rust::build-all \
  just --unstable c::build-all

watch-and-serve:
  just --unstable artifacts-server \
  & just --unstable rust::watch-all \
  & just --unstable c::watch-all

watch:
  just --unstable rust::watch-all \
  & just --unstable c::watch-all

artifacts-server:
  python3 -m http.server -d ./artifacts/

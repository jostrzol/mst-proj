mod rust

build:
  just --unstable rust::build-all

watch-and-serve:
  just --unstable artifacts-server \
  & just --unstable rust::watch-all

watch:
  just --unstable rust::watch-all

artifacts-server:
  python3 -m http.server -d ./artifacts/

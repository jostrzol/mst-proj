mod c
mod rust
mod zig

build:
  just --unstable rust::build-all \
  & just --unstable c::build-all \
  & just --unstable zig::build-all \
  & wait

watch-and-serve:
  just --unstable artifacts-server \
  & just --unstable watch \
  & wait

watch:
  just --unstable rust::watch-all \
  & just --unstable c::watch-all \
  & just --unstable zig::watch-all \
  & wait

artifacts-server:
  python3 -m http.server -d ./artifacts/

analyze: _venv_init
  . ./.venv/bin/activate \
  && { \
    lizard ./{c,rust,zig} \
      --exclude "./c/build/*" --exclude "./zig/*/.zig-cache/*" --exclude "./zig/*/build.zig" \
    || true; \
  }


# Private

_venv_dependency_packages := "setuptools"

_venv_init: _venv_dependencies _venv_lizard

_venv_lizard: _venv_dependencies 
  { . ./.venv/bin/activate && pip3 list 2>/dev/null | grep -q "^lizard\b"; } \
  || { just _download_lizard && cd "./.cache/lizard" && ./build.sh && python3 setup.py install; }

_download_lizard: _cache
  { test -d "./.cache/lizard" \
    || git clone "https://github.com/jostrzol/lizard.git" "./.cache/lizard"; } \
  && { cd "./.cache/lizard" && git pull; }

_cache:
  mkdir -p "./.cache"

_venv_dependencies: _venv_create
  . ./.venv/bin/activate \
  && pip3 install --dry-run {{_venv_dependency_packages}} 2>/dev/null | grep -q "^Would install"; \
  if "$?" -ne "0"; then pip3 install {{_venv_dependency_packages}}; fi
  
_venv_create:
  test -d "./.venv" || python3 -m venv ".venv"


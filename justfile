mod c
mod rust
mod zig

set unstable := true

languages := "c zig rust"

build:
  just rust::build-all \
  & just c::build-all \
  & just zig::build-all \
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
  just rust::watch-all \
  & just c::watch-all \
  & just zig::watch-all \
  & wait

artifacts-server:
  python3 -m http.server -d ./artifacts/

analyze: _venv_init _analyze_c _analyze_rust _analyze_zig

plot: analyze
  #!/usr/bin/env bash
  set -euo pipefail
  experiments=$( \
    find ./analysis/ -name '*.csv' -printf '%f\n' \
    | sed 's/-\w\+\.csv//g' | sort | uniq
  )
  for experiment in $experiments; do
    args="--out ./analysis/$experiment.svg"
    for lang in {{languages}}; do
      args="$args $lang:$(echo "./analysis/$experiment-$lang.csv")"
    done
    . ./.venv/bin/activate

    ( set -x; ./scripts/plot.py $args )
  done

install-dev: _venv_dev_dependencies

# analyze private
_analyze_c: (_analyze "c" "--exclude" "'./c/build/*'")
_analyze_rust: (_analyze "rust")
_analyze_zig: (
  _analyze "zig"
    "--exclude" "'./zig/*/.zig-cache/*'"
    "--exclude" "'./zig/*/build.zig'"
  )

_analyze LANG *FLAGS:
  mkdir -p "./analysis"
  - . ./.venv/bin/activate \
  && for proj in ./{{LANG}}/?-*; \
    do lizard "$proj" --csv {{FLAGS}} >"./analysis/$(basename "$proj")-{{LANG}}.csv"; \
  done


# venv private
_venv_dependency_packages := "setuptools matplotlib"
_venv_dev_dependency_packages := "ruff basedpyright"

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

_venv_dependencies: (_venv_install_packages _venv_dependency_packages)
_venv_dev_dependencies: (_venv_install_packages _venv_dev_dependency_packages)
_venv_install_packages *PACKAGES: _venv_create
  . ./.venv/bin/activate \
  && pip3 install --dry-run {{PACKAGES}} 2>/dev/null | grep -q "^Would install"; \
  if test "$?" -eq "0"; then pip3 install {{PACKAGES}}; fi
  
_venv_create:
  test -d "./.venv" || python3 -m venv ".venv"


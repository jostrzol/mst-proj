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

bench-os: pid-bench motor-bench blinky-bench
bench-bm: pid-bm-bench motor-bm-bench blinky-bm-bench

blinky-bench: \
  (_bench "--reports" "130" \
    "./artifacts/fast/1-blinky-c" \
    "./artifacts/fast/1-blinky-zig" \
    "./artifacts/debug/1-blinky-zig" \
    "./artifacts/fast/1-blinky-rust" \
  )
motor-bench: \
  (_bench "--reports" "130" \
    "./artifacts/fast/2-motor-c" \
    "./artifacts/fast/2-motor-zig" \
    "./artifacts/debug/2-motor-zig" \
    "./artifacts/fast/2-motor-rust" \
  ) 
pid-bench: \
  (_bench "--reports" "130" \
    "./artifacts/fast/3-pid-c" \
    "./artifacts/fast/3-pid-zig" \
    "./artifacts/debug/2-motor-zig" \
    "./artifacts/fast/3-pid-rust" \
  )

blinky-bm-bench: \
  (_bench-bm "--reports" "130" \
    "./artifacts/fast/1-blinky-bm-c.elf" \
    "./artifacts/fast/1-blinky-bm-zig.elf" \
    "./artifacts/fast/1-blinky-bm-rust.elf" \
  )
motor-bm-bench: \
  (_bench-bm "--reports" "130" \
    "./artifacts/fast/2-motor-bm-c.elf" \
    "./artifacts/fast/2-motor-bm-zig.elf" \
    "./artifacts/fast/2-motor-bm-rust.elf" \
  ) 
pid-bm-bench: \
  (_bench-bm "--reports" "130" \
    "./artifacts/fast/3-pid-bm-c.elf" \
    "./artifacts/fast/3-pid-bm-zig.elf" \
    "./artifacts/fast/3-pid-bm-rust.elf" \
  )

_bench *ARGS:
  ./.venv/bin/python3 ./scripts/benchmark.py {{ARGS}}

_bench-bm *ARGS:
  ./.venv/bin/python3 ./scripts/benchmark_bm.py {{ARGS}}

analyze: _venv_init _analyze_c _analyze_rust _analyze_zig

plot: analyze plot-only

plot-only:
  mkdir -p "./analysis/plots/"
  for file in ./scripts/plot_*.py; do \
    echo {{BOLD}}  \-\> running "'$file'..." && \
    ./.venv/bin/python3 "$file"; \
  done
  if test -d "{{thesis_dir}}"; then \
    mkdir -p "{{thesis_dir}}/sdm2-2/img/plots" \
    && cp ./analysis/plots/*.pdf "{{thesis_dir}}/sdm2-2/img/plots"; \
  fi

install-dev: _venv_dev_dependencies

# analyze private
_analyze_c: (
  _analyze "c"
    "--exclude" "'./c/build/*'"
    "--exclude" "'./*/build/*'"
    "--exclude" "'./*/managed_components/*'"
  )
_analyze_rust: (
  _analyze "rust"
    "--exclude" "'./*/target/*'"
    "--exclude" "'./*/.embuild/*'"
  )
_analyze_zig: (
  _analyze "zig"
    "--exclude" "'./zig/*/.zig-cache/*'"
    "--exclude" "'./zig/*/build.zig'"
    "--exclude" "'./*/build/*'"
    "--exclude" "'./*/imports/*'"
    "--exclude" "'./*/.zig-cache/*'"
    "--exclude" "'./*/managed_components/*'"
    "--exclude" "'./*/comptime-rt.zig'"
  )

_analyze LANG *FLAGS:
  mkdir -p "./analysis"
  - . ./.venv/bin/activate \
  && for proj in ./{{LANG}}/?-*; \
    do lizard "$proj" --csv {{FLAGS}} >"./analysis/$(basename "$proj")-{{LANG}}.csv"; \
  done


# venv private
_venv_dependency_packages := "setuptools matplotlib pandas numpy"
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


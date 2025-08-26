# ===== BUILD =================================================================
add_executable(1-blinky main.c memory.c perf.c)
target_compile_options(1-blinky PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(1-blinky libgpiod)
add_dependencies(1-blinky toolchain)

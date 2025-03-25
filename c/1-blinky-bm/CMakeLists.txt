# ===== BUILD =================================================================
add_executable(1-blinky-bm main.c)
target_compile_options(1-blinky-bm PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(1-blinky-bm libgpiod)

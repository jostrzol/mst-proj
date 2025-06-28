# ===== BUILD =================================================================
add_executable(2-motor main.c memory.c perf.c)
target_compile_options(2-motor PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(2-motor pigpio)
target_link_libraries(2-motor i2c-tools)

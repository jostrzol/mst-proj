# ===== BUILD =================================================================
add_executable(2-motor-controller main.c)
target_compile_options(2-motor-controller PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(2-motor-controller pigpio)
target_link_libraries(2-motor-controller i2c-tools)
target_link_libraries(2-motor-controller m)

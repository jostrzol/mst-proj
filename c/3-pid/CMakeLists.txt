# ===== BUILD =================================================================
add_executable(
  3-pid
  main.c
  memory.c
  perf.c
  server.c
  controller.c
  ringbuffer.c
  registers.c)
target_compile_options(3-pid PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(3-pid pigpio)
target_link_libraries(3-pid i2c-tools)
target_link_libraries(3-pid libmodbus)
target_link_libraries(3-pid m)
add_dependencies(3-pid toolchain)

target_compile_definitions(
  3-pid PRIVATE REVOLUTION_THRESHOLD_CLOSE="$ENV{REVOLUTION_THRESHOLD_CLOSE}")
target_compile_definitions(
  3-pid PRIVATE REVOLUTION_THRESHOLD_FAR="$ENV{REVOLUTION_THRESHOLD_FAR}")

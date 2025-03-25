cmake_minimum_required(VERSION 3.10)
project("Master thesis project: c" VERSION 0.1.0)
cmake_policy(SET CMP0135 NEW)

set(CMAKE_BUILD_TYPE Debug)

# ===== CROSS COMPILE OPTIONS =================================================
include(./toolchain.cmake)

# ===== COMPILE OPTIONS =======================================================
set(CMAKE_C_STANDARD 23)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)

# ===== ADD DEPENDENCIES ======================================================
include(./dependencies/libgpio.cmake)
include(./dependencies/pigpio.cmake)
include(./dependencies/i2c-tools.cmake)
include(./dependencies/modbus.cmake)

# ===== MAKE TARGETS ==========================================================
add_subdirectory(1-blinky)
add_subdirectory(1-blinky-bm)
add_subdirectory(2-motor-controller)
add_subdirectory(3-pid)

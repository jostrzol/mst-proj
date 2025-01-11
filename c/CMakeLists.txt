cmake_minimum_required(VERSION 3.10)
project("Master thesis project: c" VERSION 0.1.0)

# ===== CROSS COMPILE OPTIONS =================================================
include(./toolchain.cmake)

# ===== COMPILE OPTIONS =======================================================
set(CMAKE_C_STANDARD 23)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)

# ===== ADD DEPENDENCIES ======================================================
include(./dependencies/libgpio.cmake)
include(./dependencies/pigpio.cmake)

# ===== MAKE TARGETS ==========================================================
add_subdirectory(1-hello-world)
add_subdirectory(2-motor-controller)

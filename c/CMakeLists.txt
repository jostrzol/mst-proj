cmake_minimum_required(VERSION 3.10)
project("Master thesis project: c" VERSION 0.1.0)
cmake_policy(SET CMP0135 NEW)

# ===== CROSS COMPILE OPTIONS =================================================
include(./toolchain.cmake)

# ===== COMPILE OPTIONS =======================================================
set(CMAKE_C_STANDARD 23)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)

# ===== ADD DEPENDENCIES ======================================================
include(./dependencies/toolchain.cmake)
include(dependencies.cmake OPTIONAL)

# ===== COMPILE DEFINITIONS ===================================================
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  add_compile_definitions(DEBUG=1)
endif()

# ===== MAKE TARGETS ==========================================================
include(targets.cmake OPTIONAL)

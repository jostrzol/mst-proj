cmake_minimum_required(VERSION 3.10)
project("Master thesis project: c" VERSION 0.1.0)

include(FetchContent)
include(ExternalProject)
include(FindPkgConfig)
file(
  DOWNLOAD
  https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.38.3/CPM.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/cmake/CPM.cmake
  EXPECTED_HASH
    SHA256=cc155ce02e7945e7b8967ddfaff0b050e958a723ef7aad3766d368940cb15494)
include(${CMAKE_CURRENT_BINARY_DIR}/cmake/CPM.cmake)

# ===== CROSS COMPILE OPTIONS =================================================
# the name of the target operating system
set(CMAKE_SYSTEM_NAME Linux)

# which compilers to use for C and C++
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

# where is the target environment located
set(CMAKE_FIND_ROOT_PATH /usr/arm-linux-gnueabihf)

# adjust the default behavior of the FIND_XXX() commands: search programs in the
# host environment
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# search headers and libraries in the target environment
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# ===== COMPILE OPTIONS =======================================================
set(CMAKE_C_STANDARD 23)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)

# cpmaddpackage(
# "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git#v2.0.1")

# if(libgpiod_ADDED) set(ENV${CC} ${CMAKE_C_COMPILER}) set(ENV${CXX}
# ${CMAKE_CXX_COMPILER})

# # Configure execute_process( OUTPUT_QUIET COMMAND
# ${libgpiod_SOURCE_DIR}/autogen.sh --host=${CMAKE_SYSTEM_PROCESSOR}
# -enable-tools=no --prefix=${libgpiod_BINARY_DIR} WORKING_DIRECTORY
# ${libgpiod_BINARY_DIR})

# # Build execute_process( OUTPUT_QUIET COMMAND make WORKING_DIRECTORY
# ${libgpiod_BINARY_DIR})

# # Install execute_process( OUTPUT_QUIET COMMAND make install WORKING_DIRECTORY
# ${libgpiod_BINARY_DIR}) endif()

FetchContent_Declare(
  libgpiod
  GIT_REPOSITORY "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git"
  GIT_TAG v2.0.1
  UPDATE_DISCONNECTED ON)
FetchContent_MakeAvailable(libgpiod)

set(libgpiod_INSTALL_DIR ${libgpiod_BINARY_DIR}/install)

message("${libgpiod_INSTALL_DIR}")

add_custom_command(
  OUTPUT ${libgpiod_BINARY_DIR}/Makefile
  COMMAND ${libgpiod_SOURCE_DIR}/autogen.sh --host=${CMAKE_SYSTEM_PROCESSOR}
          --prefix=${libgpiod_INSTALL_DIR}
  WORKING_DIRECTORY ${libgpiod_BINARY_DIR})

add_custom_target(
  libgpiod_make
  COMMAND make
  DEPENDS ${libgpiod_BINARY_DIR}/Makefile
  WORKING_DIRECTORY ${libgpiod_BINARY_DIR})

add_custom_command(
  OUTPUT ${libgpiod_INSTALL_DIR}/lib/libgpiod.a
  COMMAND make install
  DEPENDS libgpiod_make
  WORKING_DIRECTORY ${libgpiod_BINARY_DIR})

# message(${libgpiod_POPULATED}) message(${gpiod_FOUND})

# if(NOT libgpiod_POPULATED AND NOT gpiod_FOUND) FetchContent_Populate(libgpiod)

# set(ENV${CC} ${CMAKE_C_COMPILER}) set(ENV${CXX} ${CMAKE_CXX_COMPILER})

# # Configure execute_process( OUTPUT_QUIET COMMAND
# ${libgpiod_SOURCE_DIR}/autogen.sh --host=${CMAKE_SYSTEM_PROCESSOR}
# -enable-tools=no --prefix=${libgpiod_BINARY_DIR} WORKING_DIRECTORY
# ${libgpiod_BINARY_DIR})

# # Build execute_process( OUTPUT_QUIET COMMAND make WORKING_DIRECTORY
# ${libgpiod_BINARY_DIR})

# # Install execute_process( OUTPUT_QUIET COMMAND make install WORKING_DIRECTORY
# ${libgpiod_BINARY_DIR})

# pkg_check_modules(gpiod REQUIRED IMPORTED_TARGET libgpiod) endif()

add_executable(1-hello-world ./1-hello-world/main.c)
target_compile_options(1-hello-world PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(1-hello-world
                           PRIVATE ${libgpiod_INSTALL_DIR}/include)
target_link_directories(1-hello-world PRIVATE ${libgpiod_INSTALL_DIR}/lib)
set_property(
  TARGET 1-hello-world
  APPEND
  PROPERTY OBJECT_DEPENDS ${libgpiod_INSTALL_DIR}/lib/libgpiod.a)

cmake_minimum_required(VERSION 3.10)

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

set(HELLO_WORLD "1-hello-world-c")
project(${HELLO_WORLD} VERSION 0.1.0)
add_executable(${HELLO_WORLD} ./1-hello-world/main.c)
target_compile_options(${HELLO_WORLD} PRIVATE -Wall -Wextra -Wpedantic -Werror)

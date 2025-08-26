# Provides `pigpio` library target

include(ExternalProject)

set(PIGPIO_PREFIX "${CMAKE_BINARY_DIR}/_deps/pigpio")
set(PIGPIO_LIBRARY "${PIGPIO_PREFIX}/lib/libpigpio.so")
set(PIGPIO_INCLUDE_DIR "${PIGPIO_PREFIX}/include")
set(PIGPIO_HEADER "${PIGPIO_INCLUDE_DIR}/pigpio.h")
set(PIGPIO_BUILD "${PIGPIO_PREFIX}/src/pigpio_git-build")

# ===== FETCH, CONFIGURE, BUILD, INSTALL ======================================

ExternalProject_Add(
  pigpio_git
  PREFIX "${PIGPIO_PREFIX}"
  GIT_REPOSITORY "https://github.com/joan2937/pigpio.git"
  GIT_TAG v79
  UPDATE_DISCONNECTED ON
  CMAKE_ARGS --install-prefix=${PIGPIO_PREFIX}
             --toolchain=${CMAKE_SOURCE_DIR}/toolchain.cmake
             -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  BUILD_BYPRODUCTS "${PIGPIO_LIBRARY}")
add_dependencies(pigpio_git toolchain)

# ===== MAKE TARGET ===========================================================
# hack needed to avoid errors about non-existing directory
file(MAKE_DIRECTORY "${PIGPIO_INCLUDE_DIR}")

add_library(pigpio SHARED IMPORTED)
add_dependencies(pigpio pigpio_git)
set_target_properties(
  pigpio PROPERTIES IMPORTED_LOCATION "${PIGPIO_LIBRARY}"
                    INTERFACE_INCLUDE_DIRECTORIES "${PIGPIO_INCLUDE_DIR}")

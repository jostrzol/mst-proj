# Provides `libgpiod` library target

include(FetchContent)

# ===== FETCH =================================================================
FetchContent_Declare(
  libgpiod_git
  GIT_REPOSITORY "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git"
  GIT_TAG v2.0.1
  UPDATE_DISCONNECTED ON)
FetchContent_MakeAvailable(libgpiod_git)

# ===== BUILD =================================================================
set(libgpiod_git_INSTALL_DIR ${libgpiod_git_BINARY_DIR}/install)

add_custom_command(
  OUTPUT ${libgpiod_git_BINARY_DIR}/Makefile
  COMMAND ${libgpiod_git_SOURCE_DIR}/autogen.sh --host=${CMAKE_SYSTEM_PROCESSOR}
          --prefix=${libgpiod_git_INSTALL_DIR}
  WORKING_DIRECTORY ${libgpiod_git_BINARY_DIR})

add_custom_target(
  libgpiod_make
  COMMAND make
  DEPENDS ${libgpiod_git_BINARY_DIR}/Makefile
  WORKING_DIRECTORY ${libgpiod_git_BINARY_DIR})

add_custom_command(
  OUTPUT ${libgpiod_git_INSTALL_DIR}/lib/libgpiod.a
  COMMAND make install
  DEPENDS libgpiod_make
  WORKING_DIRECTORY ${libgpiod_git_BINARY_DIR})

add_custom_target(libgpiod_bin
                  DEPENDS ${libgpiod_git_INSTALL_DIR}/lib/libgpiod.a)

# ===== MAKE TARGET ===========================================================
add_library(libgpiod SHARED IMPORTED)
add_dependencies(libgpiod libgpiod_bin)
set_target_properties(
  libgpiod PROPERTIES IMPORTED_LOCATION
                      ${libgpiod_git_INSTALL_DIR}/lib/libgpiod.a)
target_include_directories(libgpiod
                           INTERFACE ${libgpiod_git_SOURCE_DIR}/include)

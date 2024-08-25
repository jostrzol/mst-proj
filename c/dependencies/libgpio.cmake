# Provides `libgpiod` library target

include(ExternalProject)

set(LIBGPIOD_PREFIX "${CMAKE_BINARY_DIR}/_deps/libgpiod")
set(LIBGPIOD_LIBRARY "${LIBGPIOD_PREFIX}/lib/libgpiod.so.2")
set(LIBGPIOD_INCLUDE_DIR "${LIBGPIOD_PREFIX}/include")
set(LIBGPIOD_HEADER "${LIBGPIOD_INCLUDE_DIR}/gpiod.h")

# ===== FETCH, CONFIGURE, BUILD, INSTALL ======================================

ExternalProject_Add(
  libgpiod_git
  PREFIX "${LIBGPIOD_PREFIX}"
  GIT_REPOSITORY "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git"
  GIT_TAG v1.6.5
  CONFIGURE_COMMAND <SOURCE_DIR>/autogen.sh --host=${TARGET_TRIPLET}
                    --prefix=<INSTALL_DIR>
  BUILD_COMMAND make
  INSTALL_COMMAND make install INSTALL_BYPRODUCTS "${LIBGPIOD_LIBRARY}"
                  "${LIBGPIOD_HEADER}")

# ===== MAKE TARGET ===========================================================
# hack needed to avoid errors about non-existing directory
file(MAKE_DIRECTORY "${LIBGPIOD_INCLUDE_DIR}")

add_library(libgpiod SHARED IMPORTED)
add_dependencies(libgpiod libgpiod_git)
set_target_properties(
  libgpiod PROPERTIES IMPORTED_LOCATION "${LIBGPIOD_LIBRARY}"
                      INTERFACE_INCLUDE_DIRECTORIES "${LIBGPIOD_INCLUDE_DIR}")

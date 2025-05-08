# Provides `libmodbus` library target

include(ExternalProject)

set(LIBMODBUS_PREFIX "${CMAKE_BINARY_DIR}/_deps/modbus")
set(LIBMODBUS_LIBRARY "${LIBMODBUS_PREFIX}/lib/libmodbus.so")
set(LIBMODBUS_INCLUDE_DIR "${LIBMODBUS_PREFIX}/include/modbus")
set(LIBMODBUS_HEADER "${LIBMODBUS_INCLUDE_DIR}/modbus.h")

# ===== FETCH, CONFIGURE, BUILD, INSTALL ======================================

ExternalProject_Add(
  libmodbus_src
  PREFIX "${LIBMODBUS_PREFIX}"
  GIT_REPOSITORY "https://github.com/stephane/libmodbus.git"
  GIT_TAG v3.1.6
  UPDATE_DISCONNECTED ON
  BUILD_IN_SOURCE true
  CONFIGURE_COMMAND ./autogen.sh && ./configure
                    --host=${TARGET_TRIPLET}
                    --prefix=<INSTALL_DIR>
                    CC=${CMAKE_C_COMPILER}
                    CXX=${CMAKE_CXX_COMPILER}
  BUILD_COMMAND make
  INSTALL_COMMAND make install INSTALL_BYPRODUCTS "${LIBMODBUS_LIBRARY}"
                  "${LIBMODBUS_HEADER}")

# ===== MAKE TARGET ===========================================================
# hack needed to avoid errors about non-existing directory
file(MAKE_DIRECTORY "${LIBMODBUS_INCLUDE_DIR}")

add_library(libmodbus SHARED IMPORTED)
add_dependencies(libmodbus libmodbus_src)
set_target_properties(
  libmodbus PROPERTIES IMPORTED_LOCATION "${LIBMODBUS_LIBRARY}"
                      INTERFACE_INCLUDE_DIRECTORIES "${LIBMODBUS_INCLUDE_DIR}")

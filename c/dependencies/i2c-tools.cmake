# Provides `i2c-tools` library target

include(ExternalProject)

set(I2C_TOOLS_PREFIX "${CMAKE_BINARY_DIR}/_deps/i2c-tools")
set(I2C_TOOLS_LIBRARY "${I2C_TOOLS_PREFIX}/lib/libi2c.so")
set(I2C_TOOLS_INCLUDE_DIR "${I2C_TOOLS_PREFIX}/include")
set(I2C_TOOLS_HEADER "${I2C_TOOLS_INCLUDE_DIR}/i2c/smbus.h")

# ===== FETCH, CONFIGURE, BUILD, INSTALL ======================================

ExternalProject_Add(
  i2c-tools_source
  PREFIX "${I2C_TOOLS_PREFIX}"
  URL "https://www.kernel.org/pub/software/utils/i2c-tools/i2c-tools-4.4.tar.gz"
  URL_HASH
    SHA256=04d1e3b0cd88df8fb96e7709f374dd0b3561191b4c0363eaf873a074b8b7cb22
  UPDATE_DISCONNECTED ON
  CONFIGURE_COMMAND ""
  BUILD_IN_SOURCE true
  BUILD_COMMAND CC=${CMAKE_C_COMPILER} make
  INSTALL_COMMAND PREFIX=<INSTALL_DIR> make install INSTALL_BYPRODUCTS
                  "${I2C_TOOLS_LIBRARY}" "${I2C_TOOLS_HEADER}")
add_dependencies(i2c-tools_source toolchain)

# ===== MAKE TARGET ===========================================================
# hack needed to avoid errors about non-existing directory
file(MAKE_DIRECTORY "${I2C_TOOLS_INCLUDE_DIR}")

add_library(i2c-tools SHARED IMPORTED)
add_dependencies(i2c-tools i2c-tools_source)
set_target_properties(
  i2c-tools PROPERTIES IMPORTED_LOCATION "${I2C_TOOLS_LIBRARY}"
                       INTERFACE_INCLUDE_DIRECTORIES "${I2C_TOOLS_INCLUDE_DIR}")

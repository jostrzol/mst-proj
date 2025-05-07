set(TOOLCHAIN_ARCHIVE_NAME "cross-gcc-${GCC_VERSION}-pi_0-1.tar.gz")

set(TOOLCHAIN_BASE_URL
    "https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/Bookworm/GCC%2012.2.0/Raspberry%20Pi%201%2C%20Zero"
)
set(TOOLCHAIN_URL "${TOOLCHAIN_BASE_URL}/${TOOLCHAIN_ARCHIVE_NAME}/download")

set(TOOLCHAIN_ARCHIVE "${CMAKE_BINARY_DIR}/${TOOLCHAIN_ARCHIVE_NAME}")
set(TOOLCHAIN_DIR "${CMAKE_BINARY_DIR}/cross-pi-gcc-${GCC_VERSION}-0")

if(NOT EXISTS "${TOOLCHAIN_ARCHIVE}")
  message("Downloading ${TARGET_TRIPLET}-gcc-${GCC_VERSION} toolchain")
  file(DOWNLOAD "${TOOLCHAIN_URL}" "${TOOLCHAIN_ARCHIVE}" SHOW_PROGRESS)
endif()

if(NOT EXISTS "${TOOLCHAIN_DIR}")
  message("Extracting ${TARGET_TRIPLET}-gcc-${GCC_VERSION} toolchain")
  execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf ${TOOLCHAIN_ARCHIVE}
                  WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
endif()

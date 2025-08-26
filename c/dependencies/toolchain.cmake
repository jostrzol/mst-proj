set(TOOLCHAIN_ARCHIVE_NAME "cross-gcc-${GCC_VERSION}-pi_0-1.tar.gz")

set(TOOLCHAIN_BASE_URL
    "https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/Bookworm/GCC%2014.2.0/Raspberry%20Pi%201%2C%20Zero"
)
set(TOOLCHAIN_URL "${TOOLCHAIN_BASE_URL}/${TOOLCHAIN_ARCHIVE_NAME}/download")

set(TOOLCHAIN_ARCHIVE "${CMAKE_BINARY_DIR}/${TOOLCHAIN_ARCHIVE_NAME}")
set(TOOLCHAIN_DIR "${CMAKE_BINARY_DIR}/cross-pi-gcc-${GCC_VERSION}-0")

# Create a custom target for toolchain download and extraction
add_custom_target(toolchain
    COMMENT "Setting up ARM cross-compilation toolchain"
)

# Download toolchain archive if it doesn't exist
add_custom_command(
    OUTPUT "${TOOLCHAIN_ARCHIVE}"
    COMMAND ${CMAKE_COMMAND} -E echo "Downloading ${TARGET_TRIPLET}-gcc-${GCC_VERSION} toolchain"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}"
    COMMAND wget -O "${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}" || curl -L -o "${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}"
    COMMENT "Downloading toolchain archive"
    VERBATIM
)

# Extract toolchain if directory doesn't exist
add_custom_command(
    OUTPUT "${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLET}-gcc"
    DEPENDS "${TOOLCHAIN_ARCHIVE}"
    COMMAND ${CMAKE_COMMAND} -E echo "Extracting ${TARGET_TRIPLET}-gcc-${GCC_VERSION} toolchain"
    COMMAND ${CMAKE_COMMAND} -E tar xf "${TOOLCHAIN_ARCHIVE}"
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
    COMMENT "Extracting toolchain"
    VERBATIM
)

# Make toolchain target depend on the extracted gcc binary
add_custom_target(toolchain-ready
    DEPENDS "${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLET}-gcc"
    COMMENT "ARM toolchain ready"
)

# Add dependency to main toolchain target
add_dependencies(toolchain toolchain-ready)

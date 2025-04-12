set(DEPS pthread driver esp_adc)

idf_component_register(SRCS "placeholder.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES "${DEPS}"
)

include(../cmake/zig-build.cmake)

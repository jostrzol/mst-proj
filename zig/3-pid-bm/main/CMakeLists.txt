set(DEPS esp_adc esp_driver_ledc esp_driver_gpio esp_wifi nvs_flash)

idf_component_register(SRCS "placeholder.c" INCLUDE_DIRS "." PRIV_REQUIRES
                       "${DEPS}")

include(../cmake/zig-build.cmake)

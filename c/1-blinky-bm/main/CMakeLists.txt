idf_component_register(SRCS main.c memory.c perf.c
                       PRIV_REQUIRES spi_flash esp_driver_gpio
                       INCLUDE_DIRS "")

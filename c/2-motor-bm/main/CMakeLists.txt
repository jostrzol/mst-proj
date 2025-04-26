idf_component_register(SRCS main.c memory.c
                       PRIV_REQUIRES spi_flash esp_adc esp_driver_ledc esp_driver_gpio
                       INCLUDE_DIRS "")

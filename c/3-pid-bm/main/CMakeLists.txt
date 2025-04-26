idf_component_register(
  SRCS 
    main.c 
    memory.c 
    wifi.c
    registers.c
    services.c
    server.c 
    controller.c
    ringbuffer.c
  PRIV_REQUIRES spi_flash esp_adc esp_driver_ledc esp_wifi nvs_flash
  INCLUDE_DIRS "")

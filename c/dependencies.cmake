add_custom_target(dependencies COMMENT "Project depencencies")

include(./dependencies/libgpio.cmake)
include(./dependencies/pigpio.cmake)
include(./dependencies/i2c-tools.cmake)
include(./dependencies/modbus.cmake)

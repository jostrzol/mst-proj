#include <bits/types/siginfo_t.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/timerfd.h>
#include <unistd.h>

#include <i2c/smbus.h>
#include <linux/i2c-dev.h>
#include <pigpio.h>

#include "controller.h"
#include "units.h"

#define I2C_ADAPTER_NUMBER "1"
const char I2C_ADAPTER_PATH[] = "/dev/i2c-" I2C_ADAPTER_NUMBER;
const uint32_t ADS7830_ADDRESS = 0x48;
const uint32_t MOTOR_LINE_NUMBER = 13;

const uint64_t PWM_FREQUENCY = 1000;
const uint64_t READ_RATE = 60;
const uint64_t SLEEP_DURATION_US = 1e6 / READ_RATE;

// bit    7: single-ended inputs mode
// bits 6-4: channel selection
// bit    3: is internal reference enabled
// bit    2: is converter enabled
// bits 1-0: unused
const uint8_t DEFAULT_READ_COMMAND = 0b10001100;
#define MAKE_READ_COMMAND(channel) (DEFAULT_READ_COMMAND & (channel << 4))

int32_t read_potentiometer_value(int i2c_file)
{
    if (i2c_smbus_write_byte(i2c_file, MAKE_READ_COMMAND(0)) < 0) {
        perror("writing i2c ADC command failed\n");
        return -1;
    }

    int32_t value = i2c_smbus_read_byte(i2c_file);
    if (value < 0) {
        perror("reading i2c ADC value failed\n");
        return -1;
    }

    return value;
}

struct itimerspec interval_from_us(uint64_t us)
{
    return (struct itimerspec){
        .it_interval =
            {
                .tv_sec = us / MICRO_PER_1,
                .tv_nsec = (us * NANO_PER_MIRCO) % NANO_PER_1,
            },
    };
}

int controller_init(controller_t *self, controller_options_t options)
{
    int i2c_fd = open(I2C_ADAPTER_PATH, O_RDWR);
    if (i2c_fd < 0)
        goto fail;

    if (ioctl(i2c_fd, I2C_SLAVE, ADS7830_ADDRESS) != 0)
        goto fail_close_i2c;

    int read_timer_fd = timerfd_create(CLOCK_MONOTONIC, 0);
    if (read_timer_fd < 0)
        goto fail_close_i2c;

    struct itimerspec read_timerspec =
        interval_from_us(options.read_interval_us);
    if (timerfd_settime(read_timer_fd, 0, &read_timerspec, 0) != 0)
        goto fail_close_read_timer;

    int io_timer_fd = timerfd_create(CLOCK_MONOTONIC, 0);
    if (io_timer_fd < 0)
        goto fail_close_read_timer;

    struct itimerspec io_timerspec =
        interval_from_us(options.revolution_bin_rotate_interval_us);
    if (timerfd_settime(io_timer_fd, 0, &io_timerspec, 0) != 0)
        goto fail_close_io_timer;

    *self = (controller_t){
        .options = options,
        .i2c_fd = i2c_fd,
        .read_timer_fd = read_timer_fd,
        .io_timer_fd = io_timer_fd,
    };

    return EXIT_SUCCESS;

fail_close_io_timer:
    close(io_timer_fd);
fail_close_read_timer:
    close(read_timer_fd);
fail_close_i2c:
    close(i2c_fd);
fail:
    return EXIT_FAILURE;
}

int controller_handle(controller_t *self)
{
    int32_t value = read_potentiometer_value(self->read_timer_fd);
    if (value < 0)
        return EXIT_FAILURE;

    printf("selected duty cycle: %.2f\n", (double)value / UINT8_MAX);

    const uint64_t duty_cycle = PI_HW_PWM_RANGE * value / UINT8_MAX;
    if (gpioHardwarePWM(MOTOR_LINE_NUMBER, PWM_FREQUENCY, duty_cycle) != 0)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

void controller_close(controller_t *self)
{
    if (close(self->io_timer_fd) != 0)
        perror("Failed to close IO timer");
    if (close(self->read_timer_fd) != 0)
        perror("Failed to close read timer");
    if (close(self->i2c_fd) != 0)
        perror("Failed to close i2c controller");

    if (gpioHardwarePWM(self->options.pwm_channel, 0, 0) != 0)
        perror("Failed to disable PWM");
    gpioTerminate();
}

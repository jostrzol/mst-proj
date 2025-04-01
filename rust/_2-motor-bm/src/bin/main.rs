#![no_std]
#![no_main]

use esp_backtrace as _;
use esp_hal::{
    analog::adc::{Adc, AdcConfig, AdcPin, Attenuation, Resolution},
    delay::Delay,
    ledc::{
        channel::{self, ChannelHW, ChannelIFace},
        timer::{self, TimerIFace},
        LSGlobalClkSource, Ledc, LowSpeed,
    },
    main, peripherals,
    time::Rate,
};
use esp_println::println;
use thiserror_no_std::Error;

// Configuration
const PWM_FREQUENCY: u32 = 1000;
const PWM_DUTY_RESOLUTION_BIT: u32 = 13;

// Derived constants
const PWM_DUTY_MAX: u32 = (1 << PWM_DUTY_RESOLUTION_BIT) - 1;

#[main]
fn main() -> ! {
    if let Err(err) = main_impl() {
        panic!("Error in main: {:?}", err);
    }
    unreachable!();
}

fn main_impl() -> Result<(), MainError> {
    println!("Controlling motor from Rust");

    let peripherals = esp_hal::init(esp_hal::Config::default());
    let motor = peripherals.GPIO5;
    let input = peripherals.GPIO32;

    let mut adc_config = AdcConfig::<peripherals::ADC1>::new();
    let input_adc = adc_config.enable_pin(input, Attenuation::_2p5dB);
    let adc = Adc::new(peripherals.ADC1, adc_config);

    let mut ledc = Ledc::new(peripherals.LEDC);
    ledc.set_global_slow_clock(LSGlobalClkSource::APBClk);

    let mut timer = ledc.timer::<LowSpeed>(timer::Number::Timer0);
    timer.configure(timer::config::Config {
        duty: timer::config::Duty::try_from(PWM_DUTY_RESOLUTION_BIT).unwrap(),
        clock_source: timer::LSClockSource::APBClk,
        frequency: Rate::from_hz(PWM_FREQUENCY),
    })?;

    let mut channel = ledc.channel(channel::Number::Channel0, motor);
    channel.configure(channel::config::Config {
        timer: &timer,
        duty_pct: 0,
        pin_config: channel::config::PinConfig::PushPull,
    })?;

    let delay = Delay::new();
    loop {
        let duty_cycle = (0.1 * PWM_DUTY_MAX as f32) as u32;
        channel.set_duty_hw(duty_cycle);

        delay.delay_millis(500);

        let duty_cycle = (0.2 * PWM_DUTY_MAX as f32) as u32;
        channel.set_duty_hw(duty_cycle);
        delay.delay_millis(500);
    }
}

#[derive(Error, Debug)]
pub enum MainError {
    Timer(#[from] timer::Error),
    Channel(#[from] channel::Error),
}

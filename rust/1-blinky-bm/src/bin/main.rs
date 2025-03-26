#![no_std]
#![no_main]

use esp_backtrace as _;
use esp_hal::{
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    main,
};
use esp_println::println;

const PERIOD_MS: u32 = 1000;
const SLEEP_DURATION_MS: u32 = PERIOD_MS / 2;

#[main]
fn main() -> ! {
    println!("Blinking an LED from Rust");

    let peripherals = esp_hal::init(esp_hal::Config::default());

    let mut led = Output::new(peripherals.GPIO5, Level::Low, OutputConfig::default());

    let delay = Delay::new();

    loop {
        println!(
            "Turning the LED {}",
            if led.is_set_low() { "ON" } else { "OFF" }
        );

        led.toggle();
        delay.delay_millis(SLEEP_DURATION_MS);
    }
}

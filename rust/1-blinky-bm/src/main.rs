#![feature(asm_experimental_arch)]
#![feature(vec_push_within_capacity)]

mod memory;
mod perf;

use esp_idf_hal::delay::Delay;
use esp_idf_hal::gpio::*;
use esp_idf_hal::peripherals::Peripherals;
use memory::memory_report;

const BLINK_FREQUENCY: u32 = 10;
const UPDATE_FREQUENCY: u32 = BLINK_FREQUENCY * 2;
const SLEEP_DURATION_MS: u32 = 1000 / UPDATE_FREQUENCY;

fn main() -> anyhow::Result<()> {
    esp_idf_hal::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    log::info!("Controlling an LED from Rust");

    let peripherals = Peripherals::take()?;
    let mut led = PinDriver::output(peripherals.pins.gpio5)?;

    let delay = Delay::default();

    let mut perf = perf::Counter::new("MAIN", UPDATE_FREQUENCY as usize * 2)?;
    let mut report_number: u64 = 0;
    loop {
        for _ in 0..UPDATE_FREQUENCY {
            delay.delay_ms(SLEEP_DURATION_MS);

            let _measure = perf.measure();

            #[cfg(debug_assertions)]
            log::debug!(
                "Turning the LED {}",
                if led.is_set_low() { "ON" } else { "OFF" }
            );
            led.toggle()?;
        }
        println!("# REPORT {report_number}");
        memory_report();
        perf.report();
        perf.reset();
        report_number += 1;
    }
}

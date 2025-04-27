#![feature(asm_experimental_arch)]

mod memory;
mod perf;

use esp_idf_hal::delay::Delay;
use esp_idf_hal::gpio::*;
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_sys::xTaskGetCurrentTaskHandle;
use memory::memory_report;

const PERIOD_MS: u32 = 1000;
const SLEEP_DURATION_MS: u32 = PERIOD_MS / 2;
const CONTROL_ITERS_PER_PERF_REPORT: usize = 2;

fn main() -> anyhow::Result<()> {
    esp_idf_hal::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    log::info!("Controlling an LED from Rust");

    let peripherals = Peripherals::take()?;
    let mut led = PinDriver::output(peripherals.pins.gpio5)?;

    let delay = Delay::default();
    let task = unsafe { xTaskGetCurrentTaskHandle() };
    let mut perf = perf::Counter::new("MAIN")?;

    loop {
        for _ in 0..CONTROL_ITERS_PER_PERF_REPORT {
            delay.delay_ms(SLEEP_DURATION_MS);

            let _measure = perf.measure();

            log::debug!(
                "Turning the LED {}",
                if led.is_set_low() { "ON" } else { "OFF" }
            );
            led.toggle()?;
        }
        memory_report(&[task]);
        perf.report();
        perf.reset();
    }
}

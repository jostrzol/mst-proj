use esp_idf_hal::delay::FreeRtos;
use esp_idf_hal::gpio::*;
use esp_idf_hal::peripherals::Peripherals;

const PERIOD_MS: u32 = 1000;
const SLEEP_DURATION_MS: u32 = PERIOD_MS / 2;

fn main() -> anyhow::Result<()> {
    esp_idf_hal::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    log::info!("Controlling an LED from Rust");

    let peripherals = Peripherals::take()?;
    let mut led = PinDriver::output(peripherals.pins.gpio5)?;

    loop {
        log::info!(
            "Turning the LED {}",
            if led.is_set_low() { "ON" } else { "OFF" }
        );
        led.toggle()?;
        FreeRtos::delay_ms(SLEEP_DURATION_MS);
    }
}

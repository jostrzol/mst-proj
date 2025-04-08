mod services;

use esp_idf_svc::hal::prelude::Peripherals;
use esp_idf_svc::log::EspLogger;

use log::info;
use services::Services;

const SSID: &str = env!("WIFI_SSID");
const PASSWORD: &str = env!("WIFI_PASS");

fn main() -> anyhow::Result<()> {
    esp_idf_svc::sys::link_patches();
    EspLogger::initialize_default();

    let peripherals = Peripherals::take()?;
    let _ = Services::new(peripherals.modem, SSID, PASSWORD)?;

    info!("Shutting down in 5s...");

    std::thread::sleep(core::time::Duration::from_secs(5));

    Ok(())
}

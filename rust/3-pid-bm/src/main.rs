#![feature(variant_count)]

mod registers;
mod server;
mod services;

use esp_idf_svc::hal::prelude::Peripherals;
use esp_idf_svc::log::EspLogger;

use log::info;
use registers::Registers;
use server::Server;
use services::Services;

const SSID: &str = env!("WIFI_SSID");
const PASSWORD: &str = env!("WIFI_PASS");

fn main() -> anyhow::Result<()> {
    esp_idf_svc::sys::link_patches();
    EspLogger::initialize_default();

    let peripherals = Peripherals::take()?;
    let services = Services::new(peripherals.modem, SSID, PASSWORD)?;
    let registers = Registers::new();
    let _server = Server::new(services.netif(), &registers);

    info!("Controlling motor using PID from Rust");

    loop {
        std::thread::sleep(core::time::Duration::from_secs(5));
    }
}

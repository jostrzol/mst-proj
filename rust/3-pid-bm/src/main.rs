#![feature(variant_count)]

mod registers;
mod server;
mod services;

use esp_idf_hal::cpu::Core;
use esp_idf_hal::task::thread::ThreadSpawnConfiguration;
use esp_idf_svc::hal::prelude::Peripherals;
use esp_idf_svc::log::EspLogger;

use log::info;
use registers::Registers;
use server::Server;
use services::Services;

const SSID: &str = env!("WIFI_SSID");
const PASSWORD: &str = env!("WIFI_PASS");

const STACK_SIZE: usize = 4096;

fn main() -> anyhow::Result<()> {
    esp_idf_svc::sys::link_patches();
    EspLogger::initialize_default();

    let peripherals = Peripherals::take()?;
    let services = Services::new(peripherals.modem, SSID, PASSWORD)?;
    let registers = Registers::new();
    let server = Server::new(services.netif(), &registers)?;

    ThreadSpawnConfiguration {
        name: Some("SERVER_LOOP\0".as_bytes()),
        stack_size: STACK_SIZE,
        priority: 2,
        pin_to_core: Some(Core::Core0),
        ..Default::default()
    }
    .set()?;

    let server_thread = std::thread::Builder::new().spawn(move || {
        server.run();
    })?;

    info!("Controlling motor using PID from Rust");

    loop {
        std::thread::sleep(core::time::Duration::from_secs(5));
    }

    server_thread.join().expect("Couldn't join thread");
}

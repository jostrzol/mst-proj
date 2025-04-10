#![feature(variant_count)]

mod controller;
mod registers;
mod server;
mod services;

use controller::Controller;
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
    let mut controller = Controller::new(
        peripherals.adc1,
        peripherals.pins.gpio32,
        peripherals.ledc.timer0,
        peripherals.pins.gpio5,
        peripherals.ledc.channel0,
    )?;

    ThreadSpawnConfiguration {
        name: Some("SERVER_LOOP\0".as_bytes()),
        stack_size: STACK_SIZE,
        priority: 2,
        pin_to_core: Some(Core::Core0),
        ..Default::default()
    }
    .set()?;
    let server_thread = std::thread::Builder::new().spawn(move || server.run())?;

    ThreadSpawnConfiguration {
        name: Some("CONTROLLER_LOOP\0".as_bytes()),
        stack_size: STACK_SIZE,
        priority: 24,
        pin_to_core: Some(Core::Core1),
        ..Default::default()
    }
    .set()?;
    let controller_thread = std::thread::Builder::new().spawn(move || controller.run())?;

    info!("Controlling motor using PID from Rust");

    loop {
        std::thread::sleep(core::time::Duration::from_secs(5));
    }

    [server_thread, controller_thread].map(|thread| thread.join().expect("Couldn't join thread"));
}

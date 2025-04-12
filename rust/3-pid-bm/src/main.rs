#![feature(variant_count)]

mod controller;
mod registers;
mod server;
mod services;

use std::thread;
use std::{pin::Pin, time::Duration};

use esp_idf_hal::cpu::Core;
use esp_idf_hal::task::thread::ThreadSpawnConfiguration;
use esp_idf_svc::hal::prelude::Peripherals;
use esp_idf_svc::log::EspLogger;
use log::info;

use controller::{Controller, ControllerOpts};
use registers::Registers;
use server::Server;
use services::Services;

const SSID: &str = env!("WIFI_SSID");
const PASSWORD: &str = env!("WIFI_PASS");

const CONTROLLER_OPTS: ControllerOpts = ControllerOpts {
    frequency: 1000,
    revolution_treshold_close: 0.36,
    revolution_treshold_far: 0.40,
    revolution_bins: 10,
    reads_per_bin: 100,
};

const STACK_SIZE: usize = 5120;

static mut REGISTERS: Option<Registers> = None;

fn main() -> anyhow::Result<()> {
    esp_idf_svc::sys::link_patches();
    EspLogger::initialize_default();

    let peripherals = Peripherals::take()?;
    let services = Services::new(peripherals.modem, SSID, PASSWORD)?;
    let mut registers = unsafe {
        REGISTERS = Some(Registers::new());
        #[allow(static_mut_refs)]
        Pin::new_unchecked(REGISTERS.as_mut().unwrap())
    };
    let server = Server::new(services.netif(), registers.as_ref())?;

    ThreadSpawnConfiguration {
        name: Some("SERVER_LOOP\0".as_bytes()),
        priority: 2,
        pin_to_core: Some(Core::Core0),
        ..Default::default()
    }
    .set()?;
    let _server_thread = thread::Builder::new()
        .stack_size(STACK_SIZE)
        .spawn(move || server.run().expect("Server loop failed"))?;

    ThreadSpawnConfiguration {
        name: Some("CONTROLLER_LOOP\0".as_bytes()),
        priority: 24,
        pin_to_core: Some(Core::Core1),
        ..Default::default()
    }
    .set()?;
    let _controller_thread = thread::Builder::new()
        .stack_size(STACK_SIZE)
        .spawn(move || {
            // Setup has to be inside the target task, because `Notification` relies on it.
            let mut controller = Controller::new(
                peripherals.adc1,
                peripherals.pins.gpio32,
                peripherals.ledc.timer0,
                peripherals.pins.gpio5,
                peripherals.ledc.channel0,
                peripherals.timer00,
                registers.as_mut(),
                CONTROLLER_OPTS,
            )
            .expect("Controller setup failed");
            controller.run().expect("Controller loop failed")
        })?;

    info!("Controlling motor using PID from Rust");

    loop {
        thread::sleep(Duration::from_secs(5));
    }

    #[allow(unreachable_code)]
    [_server_thread, _controller_thread].map(|thread| thread.join().expect("Couldn't join thread"));

    Ok(())
}

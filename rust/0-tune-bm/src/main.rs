#![feature(variant_count)]
#![feature(asm_experimental_arch)]
#![feature(vec_push_within_capacity)]

mod controller;
mod registers;
mod server;
mod services;

use std::thread;
use std::{ffi::c_char, pin::Pin};

use esp_idf_hal::cpu::Core;
use esp_idf_hal::delay::Delay;
use esp_idf_hal::task::thread::ThreadSpawnConfiguration;
use esp_idf_svc::hal::prelude::Peripherals;
use esp_idf_svc::log::EspLogger;
use esp_idf_sys::xTaskGetHandle;
use log::info;

use controller::{Controller, ControllerOptions};
use registers::Registers;
use server::Server;
use services::Services;

const SSID: &str = env!("WIFI_SSID");
const PASSWORD: &str = env!("WIFI_PASS");

const CONTROLLER_OPTIONS: ControllerOptions = ControllerOptions {
    control_frequency: 10,
    time_window_bins: 10,
    reads_per_bin: 100,
    revolution_threshold_close: 0.20,
    revolution_threshold_far: 0.36,
};

const STACK_SIZE: usize = 5120;
const CONTROLLER_TASK_NAME: &[u8] = "CONTROLLER_LOOP\0".as_bytes();
const SERVER_TASK_NAME: &[u8] = "SERVER_LOOP\0".as_bytes();

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
        name: Some(SERVER_TASK_NAME),
        priority: 2,
        pin_to_core: Some(Core::Core0),
        ..Default::default()
    }
    .set()?;
    let _server_thread = thread::Builder::new()
        .stack_size(STACK_SIZE)
        .spawn(move || server.run().expect("Server loop failed"))?;
    let _server_task = unsafe { xTaskGetHandle(SERVER_TASK_NAME.as_ptr() as *const c_char) };

    ThreadSpawnConfiguration {
        name: Some(CONTROLLER_TASK_NAME),
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
                peripherals.pins.gpio18,
                peripherals.ledc.channel0,
                peripherals.timer00,
                registers.as_mut(),
                CONTROLLER_OPTIONS,
            )
            .expect("Controller setup failed");
            controller.run().expect("Controller loop failed")
        })?;
    let _controller_task =
        unsafe { xTaskGetHandle(CONTROLLER_TASK_NAME.as_ptr() as *const c_char) };

    info!("Tuning motor using from Rust");

    let delay = Delay::default();
    loop {
        delay.delay_ms(10 * 1000);
    }

    #[allow(unreachable_code)]
    [_server_thread, _controller_thread].map(|thread| thread.join().expect("Couldn't join thread"));

    Ok(())
}

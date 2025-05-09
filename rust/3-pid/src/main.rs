#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]
#![feature(variant_count)]
#![feature(iter_array_chunks)]
#![feature(range_into_bounds)]
#![feature(sync_unsafe_cell)]
#![feature(never_type)]

mod memory;
mod perf;

mod controller;
mod registers;
mod server;

use std::sync::Arc;

use async_mutex::Mutex;
use controller::{Controller, ControllerOptions};
use registers::Registers;
use rppal::pwm;
use server::serve;
use tokio::signal::ctrl_c;

const READ_FREQUENCY: u32 = 1000;
const CONTROL_FREQUENCY: u32 = 10;
const READS_PER_BIN: u32 = READ_FREQUENCY / CONTROL_FREQUENCY;

const CONTROLLER_OPTIONS: ControllerOptions = ControllerOptions {
    control_frequency: CONTROL_FREQUENCY,
    time_window_bins: 10,
    reads_per_bin: READS_PER_BIN,
    revolution_treshold_close: 105,
    revolution_treshold_far: 118,
    pwm_channel: pwm::Channel::Pwm1,
    pwm_frequency: 1000.,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Controlling motor using PID from Rust");

    let state = Arc::new(Mutex::new(Registers::new()));
    let socket_addr = "0.0.0.0:5502".parse()?;

    let mut controller = Controller::new(CONTROLLER_OPTIONS, state.clone())?;

    tokio::select! {
        Err(err) = serve(socket_addr, state.clone()) => Err(err),
        Err(err) = controller.run() => Err(err),
        result = ctrl_c() => match result {
            Ok(_) => {
                println!("\nGracefully stopping");
                Ok(())
            },
            Err(err) => Err(err.into()),
        },
    }
}

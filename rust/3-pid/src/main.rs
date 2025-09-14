#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]
#![feature(variant_count)]
#![feature(iter_array_chunks)]
#![feature(range_into_bounds)]
#![feature(sync_unsafe_cell)]
#![feature(never_type)]
#![feature(vec_push_within_capacity)]
#![feature(ptr_as_ref_unchecked)]

mod memory;
mod perf;

mod controller;
mod registers;
mod server;

use std::{cell::SyncUnsafeCell, sync::Arc};

use controller::{Controller, ControllerOptions};
use registers::Registers;
use rppal::pwm;
use server::serve;
use tokio::signal::ctrl_c;

const REVOLUTION_THRESHOLD_CLOSE: &str = env!("REVOLUTION_THRESHOLD_CLOSE");
const REVOLUTION_THRESHOLD_FAR: &str = env!("REVOLUTION_THRESHOLD_FAR");

const READ_FREQUENCY: u32 = 1000;
const CONTROL_FREQUENCY: u32 = 10;
const READS_PER_BIN: u32 = READ_FREQUENCY / CONTROL_FREQUENCY;

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    println!("Controlling motor using PID from Rust");

    let state = Arc::new(SyncUnsafeCell::new(Registers::new()));
    let socket_addr = "0.0.0.0:5502".parse()?;

    let revolution_threshold_close: f32 = REVOLUTION_THRESHOLD_CLOSE
        .parse::<f32>()
        .expect("REVOLUTION_THRESHOLD_CLOSE must be a float");
    let revolution_threshold_far: f32 = REVOLUTION_THRESHOLD_FAR
        .parse::<f32>()
        .expect("REVOLUTION_THRESHOLD_FAR must be a float");
    let controller_options: ControllerOptions = ControllerOptions {
        control_frequency: CONTROL_FREQUENCY,
        time_window_bins: 10,
        reads_per_bin: READS_PER_BIN,
        revolution_threshold_close: revolution_threshold_close,
        revolution_threshold_far: revolution_threshold_far,
        pwm_channel: pwm::Channel::Pwm1,
        pwm_frequency: 1000.,
    };

    let mut controller = Controller::new(controller_options, state.clone())?;

    tokio::select! {
        Err(err) = controller.run() => Err(err),
        Err(err) = serve(socket_addr, state) => Err(err),
        result = ctrl_c() => match result {
            Ok(_) => {
                println!("\nGracefully stopping");
                Ok(())
            },
            Err(err) => Err(err.into()),
        },
    }
}

#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]
#![feature(variant_count)]
#![feature(iter_array_chunks)]
#![feature(range_into_bounds)]
#![feature(sync_unsafe_cell)]

mod memory;

mod controller;
mod server;
mod state;

use std::{sync::Arc, time::Duration};

use async_mutex::Mutex;
use controller::{run_controller, ControllerSettings};
use rppal::pwm;
use server::serve;
use state::State;
use tokio::signal::ctrl_c;

const READ_RATE: u128 = 1000;
const READ_INTERVAL: Duration =
    Duration::from_nanos((Duration::SECOND.as_nanos() / READ_RATE) as u64);

const CONTROLLER_SETTINGS: ControllerSettings = ControllerSettings {
    read_interval: READ_INTERVAL,
    revolution_treshold_close: 105,
    revolution_treshold_far: 118,
    revolution_bins: 10,
    control_interval: Duration::from_millis(100),
    pwm_channel: pwm::Channel::Pwm1,
    pwm_frequency: 1000.,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Controlling motor using PID from Rust");

    let state = Arc::new(Mutex::new(State::new()));
    let socket_addr = "0.0.0.0:5502".parse()?;

    tokio::select! {
        result = serve(socket_addr, state.clone()) => match result {
            Ok(_) => unreachable!(),
            err => err,
        },
        result = run_controller(CONTROLLER_SETTINGS, state) => match result {
            Ok(_) => unreachable!(),
            err => err,
        },
        result = ctrl_c() => match result {
            Ok(_) => {
                println!("\nGracefully stopping");
                Ok(())
            },
            Err(err) => Err(err.into()),
        },
    }
}

#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]
#![feature(variant_count)]
#![feature(iter_array_chunks)]
#![feature(range_into_bounds)]

mod pid;
mod server;
mod state;

use std::{sync::Arc, time::Duration};

use async_mutex::Mutex;
use pid::{run_pid, PidSettings};
use rppal::pwm;
use server::serve;
use state::State;
use tokio::signal::ctrl_c;

const READ_RATE: u128 = 1000;
const READ_INTERVAL: Duration =
    Duration::from_nanos((Duration::SECOND.as_nanos() / READ_RATE) as u64);

const PID_SETTINGS: PidSettings = PidSettings {
    read_interval: READ_INTERVAL,
    revolution_treshold_close: 105,
    revolution_treshold_far: 118,
    revolution_bins: 10,
    revolution_bin_rotate_interval: Duration::from_millis(100),
    pwm_channel: pwm::Channel::Pwm1,
    pwm_frequency: 1000.,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let state = Arc::new(Mutex::new(State::new()));
    let socket_addr = "0.0.0.0:5502".parse()?;

    tokio::select! {
        result = serve(socket_addr, state.clone()) => match result {
            Ok(_) => unreachable!(),
            err => err,
        },
        result = run_pid(PID_SETTINGS, state) => match result {
            Ok(_) => unreachable!(),
            err => err,
        },
        result = ctrl_c() => match result {
            Ok(_) => {
                println!("Gracefully stopping\n");
                Ok(())
            },
            Err(err) => Err(err.into()),
        },
    }
}

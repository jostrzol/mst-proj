#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]
#![feature(variant_count)]
#![feature(iter_array_chunks)]

mod pid;
mod server;
mod state;

use std::{sync::Arc, time::Duration};

use async_mutex::Mutex;
use pid::run_pid_loop;
use server::serve;
use state::State;
use tokio::signal::ctrl_c;

const READING_RATE: u128 = 3000;
const READING_INTERVAL: Duration =
    Duration::from_nanos((Duration::SECOND.as_nanos() / READING_RATE) as u64);
const READING_HISTORY_TIME: Duration = Duration::from_secs(5);
const READING_HISTORY_COUNT: usize =
    (READING_HISTORY_TIME.as_nanos() / READING_INTERVAL.as_nanos()) as usize;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let state = Arc::new(Mutex::new(State::<READING_HISTORY_COUNT>::new()));
    let socket_addr = "0.0.0.0:5502".parse()?;

    tokio::select! {
        result = serve(state.clone(), socket_addr) => match result {
            Ok(_) => unreachable!(),
            err => err,
        },
        result = run_pid_loop(READING_INTERVAL, state) => match result {
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

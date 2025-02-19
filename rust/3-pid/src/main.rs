#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]

mod pid;
mod server;
mod state;

use std::{sync::Arc, time::Duration};

use async_mutex::Mutex;
use pid::run_pid_loop;
use server::serve;
use state::State;
use tokio::signal::ctrl_c;

const READING_RATE: u64 = 1000;
const READING_INTERVAL: Duration =
    Duration::from_millis(Duration::SECOND.as_millis() as u64 / READING_RATE);
const READING_HISTORY_TIME: Duration = Duration::from_secs(5);
const READING_HISTORY_COUNT: usize =
    (READING_HISTORY_TIME.as_nanos() / READING_INTERVAL.as_nanos()) as usize;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let state = Arc::new(Mutex::new(State::<READING_HISTORY_COUNT>::new()));
    let socket_addr = "0.0.0.0:5502".parse()?;

    tokio::select! {
        _ = serve(state.clone(), socket_addr) => unreachable!(),
        _ = run_pid_loop(READING_INTERVAL, state) => unreachable!(),
        _ = ctrl_c() => println!("Gracefully stopping\n"),
    }

    Ok(())
}

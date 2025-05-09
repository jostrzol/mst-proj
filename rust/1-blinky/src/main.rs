#![feature(sync_unsafe_cell)]

mod memory;
mod perf;

use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::gpio::Gpio;

const GPIO_LED: u8 = 13;
const PERIOD_MS: u64 = 100;
const SLEEP_DURATION: Duration = Duration::from_millis(PERIOD_MS / 2);
const CONTROL_ITERS_PER_PERF_REPORT: usize = 20;

fn main() -> Result<(), Box<dyn Error>> {
    println!("Controlling an LED from Rust");

    let gpio = Gpio::new()?;
    let mut pin = gpio.get(GPIO_LED)?.into_output();

    let more_work = Arc::new(AtomicBool::new(true));
    {
        let more_work = more_work.clone();
        ctrlc::set_handler(move || {
            println!("\nGracefully stopping");
            more_work.store(false, Ordering::Relaxed)
        })?;
    }

    let mut perf = perf::Counter::new("MAIN")?;
    while more_work.load(Ordering::Relaxed) {
        for _ in 0..CONTROL_ITERS_PER_PERF_REPORT {
            thread::sleep(SLEEP_DURATION);

            let _measure = perf.measure();

            #[cfg(debug_assertions)]
            println!(
                "Turning the LED {}",
                if pin.is_set_low() { "ON" } else { "OFF" }
            );

            pin.toggle();
        }

        memory::report();
        perf.report();
        perf.reset();
    }

    pin.set_low();
    Ok(())
}

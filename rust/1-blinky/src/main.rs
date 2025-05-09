#![feature(sync_unsafe_cell)]
#![feature(vec_push_within_capacity)]

mod memory;
mod perf;

use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::gpio::Gpio;

const GPIO_LED: u8 = 13;

const BLINK_FREQUENCY: u64 = 10;
const UPDATE_FREQUENCY: u64 = BLINK_FREQUENCY * 2;
const SLEEP_DURATION: Duration = Duration::from_micros(1000000 / UPDATE_FREQUENCY);

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

    let mut perf = perf::Counter::new("MAIN", UPDATE_FREQUENCY as usize * 2)?;
    while more_work.load(Ordering::Relaxed) {
        for _ in 0..UPDATE_FREQUENCY {
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

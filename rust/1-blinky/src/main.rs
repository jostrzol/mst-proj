use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::gpio::Gpio;

const GPIO_LED: u8 = 14;
const PERIOD_MS: u64 = 1000;
const SLEEP_DURATION: Duration = Duration::from_millis(PERIOD_MS / 2);

fn main() -> Result<(), Box<dyn Error>> {
    println!("Blinking an LED from Rust.");

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

    while more_work.load(Ordering::Relaxed) {
        pin.toggle();
        thread::sleep(SLEEP_DURATION);
    }

    pin.set_low();
    Ok(())
}

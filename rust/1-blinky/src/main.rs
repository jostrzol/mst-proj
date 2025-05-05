use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::gpio::Gpio;

const GPIO_LED: u8 = 13;
const PERIOD_MS: u64 = 100;
const SLEEP_DURATION: Duration = Duration::from_millis(PERIOD_MS / 2);

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

    while more_work.load(Ordering::Relaxed) {
        thread::sleep(SLEEP_DURATION);

        #[cfg(debug_assertions)]
        println!(
            "Turning the LED {}",
            if pin.is_set_low() { "ON" } else { "OFF" }
        );

        pin.toggle();
    }

    pin.set_low();
    Ok(())
}

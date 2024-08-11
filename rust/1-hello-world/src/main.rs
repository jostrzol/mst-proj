use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::gpio::Gpio;
use rppal::system::DeviceInfo;

const GPIO_LED: u8 = 14;

fn main() -> Result<(), Box<dyn Error>> {
    println!("Blinking an LED on a {}.", DeviceInfo::new()?.model());

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
        thread::sleep(Duration::from_millis(500));
    }

    pin.set_low();
    Ok(())
}

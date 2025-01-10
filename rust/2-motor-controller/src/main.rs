use std::error::Error;
use std::f64::consts::PI;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::gpio::Gpio;

const GPIO_MOTOR: u8 = 13;
const PERIOD_MS: u64 = 5000;
const PWM_CHANGES: u64 = 50;
const PWM_MIN: f64 = 0.2;
const PWM_MAX: f64 = 1.0;
const PWM_FREQUENCY: f64 = 1000.;
const SLEEP_DURATION: Duration = Duration::from_millis(PERIOD_MS / PWM_CHANGES);

fn main() -> Result<(), Box<dyn Error>> {
    println!("Controlling motor from Rust.");

    let gpio = Gpio::new()?;
    let mut pin = gpio.get(GPIO_MOTOR)?.into_output();

    let more_work = Arc::new(AtomicBool::new(true));
    {
        let more_work = more_work.clone();
        ctrlc::set_handler(move || {
            println!("\nGracefully stopping");
            more_work.store(false, Ordering::Relaxed)
        })?;
    }

    'outer: loop {
        for i in 0..PWM_CHANGES {
            let sin = f64::sin(i as f64 / PWM_CHANGES as f64 * 2. * PI);
            let ratio = (sin + 1.) / 2.;
            let duty_cycle = PWM_MIN + ratio * (PWM_MAX - PWM_MIN);
            _ = pin
                .set_pwm_frequency(PWM_FREQUENCY, duty_cycle)
                .inspect_err(|err| eprintln!("error setting pwm frequency: {err}"));

            if !more_work.load(Ordering::Relaxed) {
                break 'outer;
            }
            thread::sleep(SLEEP_DURATION);
        }
    }

    pin.clear_pwm()?;
    Ok(())
}

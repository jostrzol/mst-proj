#![feature(duration_constants)]

use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::i2c::I2c;
use rppal::pwm::{Channel, Pwm};

const PWM_CHANNEL: Channel = Channel::Pwm1; // GPIO 13
const PWM_FREQUENCY: f64 = 1000.;
const REFRESH_RATE: u64 = 60;
const SLEEP_DURATION: Duration =
    Duration::from_millis(Duration::SECOND.as_millis() as u64 / REFRESH_RATE);

fn main() -> Result<(), Box<dyn Error>> {
    println!("Controlling motor from Rust.");

    let mut i2c = I2c::new()?;
    i2c.set_slave_address(0x48)?;

    let pwm = Pwm::new(PWM_CHANNEL)?;
    pwm.set_frequency(PWM_FREQUENCY, 0.)?;
    pwm.enable()?;

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

        let Some(value) = read_potentiometer_value(&mut i2c) else {
            continue;
        };

        let duty_cycle = value as f64 / u8::MAX as f64;
        println!("selected duty cycle: {duty_cycle:.2}");

        if let Err(err) = pwm.set_frequency(PWM_FREQUENCY, duty_cycle) {
            eprintln!("error setting pwm frequency: {err}");
        }
    }

    Ok(())
}

fn read_potentiometer_value(i2c: &mut I2c) -> Option<u8> {
    const WRITE_BUFFER: [u8; 1] = [0x84];
    let mut read_buffer = [0];

    i2c.write_read(&WRITE_BUFFER, &mut read_buffer)
        .inspect_err(|err| eprintln!("error reading potentiometer value: {err}"))
        .ok()?;
    Some(read_buffer[0])
}

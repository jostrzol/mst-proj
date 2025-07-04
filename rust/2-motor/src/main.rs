#![feature(sync_unsafe_cell)]
#![feature(duration_constants)]
#![feature(vec_push_within_capacity)]

mod memory;
mod perf;

use std::error::Error;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use rppal::i2c::{self, I2c};
use rppal::pwm::{Channel, Pwm};

const PWM_CHANNEL: Channel = Channel::Pwm1; // GPIO 13
const PWM_FREQUENCY: f64 = 1000.;

const CONTROL_FREQUENCY: u64 = 10;
const SLEEP_DURATION: Duration = Duration::from_micros(1000000 / CONTROL_FREQUENCY);

fn main() -> Result<(), Box<dyn Error>> {
    println!("Controlling motor from Rust");

    let mut i2c = I2c::new()?;
    i2c.set_slave_address(0x48)?;

    let pwm = Pwm::new(PWM_CHANNEL)?;
    pwm.set_frequency(PWM_FREQUENCY, 0.)?;
    let pwm_period = pwm.period()?;
    pwm.enable()?;

    let more_work = Arc::new(AtomicBool::new(true));
    {
        let more_work = more_work.clone();
        ctrlc::set_handler(move || {
            println!("\nGracefully stopping");
            more_work.store(false, Ordering::Relaxed)
        })?;
    }

    let mut perf = perf::Counter::new("MAIN", CONTROL_FREQUENCY as usize * 2)?;
    let mut report_number: u64 = 0;
    while more_work.load(Ordering::Relaxed) {
        for _ in 0..CONTROL_FREQUENCY {
            thread::sleep(SLEEP_DURATION);

            let _measure = perf.measure();

            let value = match read_adc(&mut i2c) {
                Ok(value) => value,
                Err(err) => {
                    eprintln!("read_adc fail: {err}");
                    continue;
                }
            };

            let duty_cycle = value as f32 / u8::MAX as f32;
            #[cfg(debug_assertions)]
            println!("selected duty cycle: {duty_cycle:.2}");

            let pulse_width = pwm_period.mul_f32(duty_cycle);
            if let Err(err) = pwm.set_pulse_width(pulse_width) {
                eprintln!("Pwm::set_pulse_width fail: {err}");
                continue;
            }
        }

        println!("# REPORT {report_number}");
        memory::report();
        perf.report();
        perf.reset();
        report_number += 1;
    }

    Ok(())
}

fn read_adc(i2c: &mut I2c) -> Result<u8, i2c::Error> {
    const WRITE_BUFFER: [u8; 1] = [make_read_command(0)];
    let mut read_buffer = [0];

    i2c.write_read(&WRITE_BUFFER, &mut read_buffer)?;
    Ok(read_buffer[0])
}

const fn make_read_command(channel: u8) -> u8 {
    // bit    7: single-ended inputs mode
    // bits 6-4: channel selection
    // bit    3: is internal reference enabled
    // bit    2: is converter enabled
    // bits 1-0: unused
    const DEFAULT_READ_COMMAND: u8 = 0b10001100;

    assert!(channel < 8);
    DEFAULT_READ_COMMAND & (channel << 4)
}

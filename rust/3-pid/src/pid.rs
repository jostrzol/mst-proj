use async_mutex::Mutex;
use rppal::i2c::I2c;
use rppal::pwm::{Channel, Pwm};
use std::error::Error;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::{interval, MissedTickBehavior};

use crate::state::State;

const PWM_CHANNEL: Channel = Channel::Pwm1; // GPIO 13
const PWM_FREQUENCY: f64 = 1000.;

fn read_potentiometer_value(i2c: &mut I2c) -> Option<u8> {
    const WRITE_BUFFER: [u8; 1] = [make_read_command(0)];
    let mut read_buffer = [0];

    i2c.write_read(&WRITE_BUFFER, &mut read_buffer)
        .inspect_err(|err| eprintln!("error reading potentiometer value: {err}"))
        .ok()?;
    Some(read_buffer[0])
}

const fn make_read_command(channel: u8) -> u8 {
    assert!(channel < 8);

    // bit    7: single-ended inputs mode
    // bits 6-4: channel selection
    // bit    3: is internal reference enabled
    // bit    2: is converter enabled
    // bits 1-0: unused
    const DEFAULT_READ_COMMAND: u8 = 0b10001100;

    DEFAULT_READ_COMMAND & (channel << 4)
}

pub async fn run_pid_loop<const CAP: usize>(
    reading_interval: Duration,
    state: Arc<Mutex<State<CAP>>>,
) -> Result<(), Box<dyn Error>> {
    println!("Controlling motor from Rust.");

    let mut i2c = I2c::new()?;
    i2c.set_slave_address(0x48)?;

    let pwm = Pwm::new(PWM_CHANNEL)?;
    pwm.set_frequency(PWM_FREQUENCY, 0.)?;
    pwm.enable()?;

    let mut interval = interval(reading_interval);
    interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
    loop {
        interval.tick().await;

        let Some(value) = read_potentiometer_value(&mut i2c) else {
            continue;
        };

        let mut state = state.lock().await;
        state.push(value);

        let duty_cycle = state.get_target();
        println!("selected duty cycle: {duty_cycle:.2}");
    }
}

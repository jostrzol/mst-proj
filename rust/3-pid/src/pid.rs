use async_mutex::Mutex;
use ringbuffer::{ConstGenericRingBuffer, RingBuffer};
use rppal::i2c::I2c;
use rppal::pwm::{Channel, Pwm};
use std::cell::{Cell, RefCell};
use std::error::Error;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::{interval, MissedTickBehavior};

use crate::state::State;

const UPDATING_INTERVAL: Duration = Duration::from_millis(100);
const UPDATING_BINS: usize = 10;
const REPORTING_INTERVAL: Duration = Duration::from_secs(1);

const PWM_CHANNEL: Channel = Channel::Pwm1; // GPIO 13
const PWM_FREQUENCY: f64 = 1000.;

const REVOLUTION_TRESHOLD_CLOSE: u8 = 90;
const REVOLUTION_TRESHOLD_FAR: u8 = 100;

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
    let mut i2c = I2c::new()?;
    i2c.set_slave_address(0x48)?;

    let pwm = Pwm::new(PWM_CHANNEL)?;
    pwm.set_frequency(PWM_FREQUENCY, 0.)?;
    pwm.enable()?;

    pwm.set_frequency(PWM_FREQUENCY, 1.)?;

    let reads = Cell::new(0);

    let mut revolutions = ConstGenericRingBuffer::<u32, UPDATING_BINS>::new();
    revolutions.fill_default();
    let revolutions = RefCell::new(revolutions);

    tokio::select! {
        _ = async {
            let mut interval = interval(reading_interval);
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

            let mut is_close: bool = false;

            loop {
                interval.tick().await;

                let Some(value) = read_potentiometer_value(&mut i2c) else {
                    continue;
                };

                let mut state = state.lock().await;
                state.push(value);

                // println!("read: {}", value);

                if value < REVOLUTION_TRESHOLD_CLOSE && !is_close {
                    // gone close
                    is_close = true;
                    let mut revolutions = revolutions.borrow_mut();
                    revolutions[UPDATING_BINS - 1] += 1;
                    // println!("revolutions: {}", revolutions);
                } else if value > REVOLUTION_TRESHOLD_FAR && is_close {
                    // gone far
                    is_close = false;
                }


                reads.set(reads.get() + 1)
            }
        } => unreachable!(),
        _ = async {
            let mut interval = interval(UPDATING_INTERVAL);
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

            loop {
                interval.tick().await;

                let sum: u32 = {
                    let mut revolutions = revolutions.borrow_mut();
                    let sum = revolutions.iter().sum();
                    revolutions.push(0);
                    sum
                };

                let frequency = sum as f32 / (UPDATING_INTERVAL.as_secs_f32() * UPDATING_BINS as f32);
                let frequency = frequency.floor() as u16;
                println!("frequency: {} Hz", frequency);

                let mut state = state.lock().await;
                state.set_current(frequency);
            }
        } => unreachable!(),
        // _ = async {
        //     let target_update_rate = Duration::SECOND.as_nanos() / reading_interval.as_nanos();
        //     let mut interval = interval(REPORTING_INTERVAL);
        //     interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
        //
        //     loop {
        //         interval.tick().await;
        //
        //         println!("update rate: {}/{} Hz", reads.take(), target_update_rate);
        //     }
        // } => unreachable!(),
    }
}

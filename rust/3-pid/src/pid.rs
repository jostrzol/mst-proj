use async_mutex::Mutex;
use ringbuffer::{ConstGenericRingBuffer, RingBuffer};
use rppal::i2c::I2c;
use rppal::pwm::{Channel, Pwm};
use std::cell::{Cell, RefCell};
use std::error::Error;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::{interval, MissedTickBehavior};

use crate::state::{InputRegister, State};

const UPDATING_INTERVAL: Duration = Duration::from_millis(100);
const UPDATING_BINS: usize = 10;

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
    pid_interval: Duration,
    state: Arc<Mutex<State<CAP>>>,
) -> Result<(), Box<dyn Error>> {
    let mut i2c = I2c::new()?;
    i2c.set_slave_address(0x48)?;

    let pwm = Pwm::new(PWM_CHANNEL)?;
    pwm.set_frequency(PWM_FREQUENCY, 0.)?;
    pwm.enable()?;

    let mut revolutions = ConstGenericRingBuffer::<u32, UPDATING_BINS>::new();
    revolutions.fill_default();
    let revolutions = RefCell::new(revolutions);

    let duty_cycle = Cell::new(0.);

    tokio::select! {
        _ = async {
            let mut interval = interval(pid_interval);
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

            let mut is_close: bool = false;

            loop {
                interval.tick().await;

                let Some(value) = read_potentiometer_value(&mut i2c) else {
                    continue;
                };

                let mut state = state.lock().await;
                state.push(value);

                if value < REVOLUTION_TRESHOLD_CLOSE && !is_close {
                    // gone close
                    is_close = true;
                    let mut revolutions = revolutions.borrow_mut();
                    revolutions[UPDATING_BINS - 1] += 1;
                } else if value > REVOLUTION_TRESHOLD_FAR && is_close {
                    // gone far
                    is_close = false;
                }

                if let Err(err) = pwm.set_frequency(PWM_FREQUENCY, duty_cycle.get()) {
                    eprintln!("error setting pwm duty cycle: {err}");
                }
            }
        } => unreachable!(),
        _ = async {
            let mut interval = interval(UPDATING_INTERVAL);
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

            let mut last_delta: f64 = 0.;
            let mut last_integration_component: f64 = 0.;

            loop {
                interval.tick().await;

                let sum: u32 = {
                    let mut revolutions = revolutions.borrow_mut();
                    let sum = revolutions.iter().sum();
                    revolutions.push(0);
                    sum
                };

                let frequency = sum as f32 / (UPDATING_INTERVAL.as_secs_f32() * UPDATING_BINS as f32);
                let current_frequency = frequency.floor() as u16;
                println!("frequency: {} Hz", current_frequency);

                let mut state = state.lock().await;
                state.write_input_registers(InputRegister::CurrentFrequency as usize, &[current_frequency]);

                let registers = state.read_holding_registers(0, 4)
                    .iter()
                    .map(|x| *x as f64)
                    .collect::<Vec<_>>();

                let [
                    target_frequency,
                    proportional_factor,
                    integration_time,
                    differentiation_time,
                ] = registers[..] else { unreachable!() };

                let integration_factor: f64 = proportional_factor / integration_time;
                let differentiation_factor: f64 = proportional_factor * differentiation_time / UPDATING_INTERVAL.as_secs_f64();

                let delta = target_frequency - current_frequency as f64;
                println!("delta: {:.2}", delta);

                let proportional_component = proportional_factor * delta;
                let integration_component = last_integration_component
                    + integration_factor * last_delta;
                let differentiation_component = differentiation_factor * (delta - last_delta);

                let control_signal = (proportional_component + integration_component + differentiation_component).clamp(0., 1.);
                println!("control signal: {:.2}", control_signal);

                duty_cycle.set(control_signal);

                last_delta = delta;
                last_integration_component = integration_component;
            }
        } => unreachable!(),
    }
}

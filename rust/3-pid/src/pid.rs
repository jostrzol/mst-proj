use async_mutex::Mutex;
use ringbuffer::{AllocRingBuffer, RingBuffer};
use rppal::i2c::I2c;
use rppal::pwm::{self, Pwm};
use std::cell::RefCell;
use std::error::Error;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::{interval, MissedTickBehavior};

use crate::state::State;

const PWM_MIN: f32 = 0.2;
const PWM_MAX: f32 = 1.0;

const LIMIT_MIN_DEADZONE: f32 = 0.001;

pub struct PidSettings {
    /// Interval between ADC reads.
    pub read_interval: Duration,
    /// When ADC reads below this signal, the state is set to `close` to the motor magnet. If the
    /// state has changed, a new revolution is counted.
    pub revolution_treshold_close: u8,
    /// When ADC reads above this signal, the state is set to `far` from the motor magnet.
    pub revolution_treshold_far: u8,
    /// Revolutions are binned in a ring buffer based on when they happened. More recent
    /// revolutions are in the tail of the buffer, while old ones are in the head of the buffer
    /// (soon to be replaced).
    ///
    /// [revolution_bins] is the number of bins in the ring buffer.
    pub revolution_bins: usize,
    /// Revolutions are binned in a ring buffer based on when they happened. More recent
    /// revolutions are in the tail of the buffer, while old ones are in the head of the buffer
    /// (soon to be replaced).
    ///
    /// [revolution_bin_rotate_interval] is the interval that each of the bins correspond to.
    ///
    /// If `revolution_bin_rotate_interval = Duration::from_millis(100)`, then:
    /// * the last bin corresponds to range `0..-100 ms` from now,
    /// * the second-to-last bin corresponds to range `-100..-200 ms` from now,
    /// * and so on.
    ///
    /// In total, frequency will be counted from revolutions in all bins, across the total interval
    /// of [revolution_bins] * [revolution_bin_rotate_interval].
    ///
    /// [revolution_bin_rotate_interval] is also the interval at which the measured frequency updates,
    /// so all the IO happens at this interval too.
    pub revolution_bin_rotate_interval: Duration,
    /// Linux PWM channel to use.
    pub pwm_channel: pwm::Channel,
    /// Frequency of the PWM signal.
    pub pwm_frequency: f64,
}

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

pub async fn run_pid(
    settings: PidSettings,
    state: Arc<Mutex<State>>,
) -> Result<(), Box<dyn Error>> {
    let mut i2c = I2c::new()?;
    i2c.set_slave_address(0x48)?;

    let pwm = Pwm::new(settings.pwm_channel)?;
    pwm.set_frequency(settings.pwm_frequency, 0.)?;
    pwm.enable()?;

    let mut revolutions = AllocRingBuffer::<u32>::new(settings.revolution_bins);
    revolutions.fill_default();
    let revolutions = RefCell::new(revolutions);

    tokio::select! {
        _ = read_loop(&settings, &revolutions, &mut i2c) => unreachable!(),
        _ = io_loop(&settings, &revolutions, pwm, state) => unreachable!(),
    }
}

async fn read_loop(
    settings: &PidSettings,
    revolutions: &RefCell<impl RingBuffer<u32>>,
    i2c: &mut I2c,
) -> ! {
    let mut interval = interval(settings.read_interval);
    interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

    let mut is_close: bool = false;

    loop {
        interval.tick().await;

        let Some(value) = read_potentiometer_value(i2c) else {
            continue;
        };

        if value < settings.revolution_treshold_close && !is_close {
            // gone close
            is_close = true;
            let mut revolutions = revolutions.borrow_mut();
            let last = revolutions.back_mut().expect("revolutions is empty");
            *last += 1;
        } else if value > settings.revolution_treshold_far && is_close {
            // gone far
            is_close = false;
        }
    }
}

async fn io_loop(
    settings: &PidSettings,
    revolutions: &RefCell<impl RingBuffer<u32>>,
    pwm: Pwm,
    state: Arc<Mutex<State>>,
) -> ! {
    let interval_duration = settings.revolution_bin_rotate_interval;
    let interval_duration_s = interval_duration.as_secs_f32();
    let all_bins_interval_s = interval_duration_s * settings.revolution_bins as f32;

    let mut interval = interval(interval_duration);
    interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

    let mut feedback = PidFeedback::default();

    loop {
        interval.tick().await;

        let revolutions_sum = sum_and_push_new(revolutions);
        let frequency = revolutions_sum as f32 / all_bins_interval_s;
        println!("frequency: {} Hz", frequency);

        let (control_signal, new_feedback) = {
            let mut state = state.lock().await;

            let calculator = PidCalculator::from_state(&state, interval_duration_s);
            let (control_signal, new_feedback) = calculator.calculate(frequency, &feedback);

            let control_signal_limited = limit(control_signal, PWM_MIN, PWM_MAX);
            println!("control_signal_limited: {:.2}", control_signal_limited);
            state.write_input_registers(.., [frequency, control_signal_limited]);

            (control_signal_limited, new_feedback)
        };

        let result = pwm.set_frequency(settings.pwm_frequency, control_signal as f64);
        if let Err(err) = result {
            eprintln!("error setting pwm duty cycle: {err}");
        }

        feedback = new_feedback;
    }
}

struct PidCalculator {
    target_frequency: f32,
    proportional_factor: f32,
    integration_factor: f32,
    differentiation_factor: f32,
}

impl PidCalculator {
    fn from_state(state: &State, interval_duration_s: f32) -> PidCalculator {
        let registers = state.read_holding_registers(..);

        #[rustfmt::skip]
        let &[
            target_frequency,
            proportional_factor,
            integration_time,
            differentiation_time
        ] = registers else { panic!("expected to read 4 registers") };

        let integration_factor = proportional_factor / integration_time * interval_duration_s;
        let differentiation_factor =
            proportional_factor * differentiation_time / interval_duration_s;

        PidCalculator {
            target_frequency,
            proportional_factor,
            integration_factor,
            differentiation_factor,
        }
    }

    fn calculate(&self, frequency: f32, feedback: &PidFeedback) -> (f32, PidFeedback) {
        let delta = self.target_frequency - frequency;

        let proportional_component = self.proportional_factor * delta;
        let integration_component =
            feedback.integration_component + self.integration_factor * feedback.delta;
        let differentiation_component = self.differentiation_factor * (delta - feedback.delta);

        let control_signal =
            proportional_component + integration_component + differentiation_component;

        println!("delta: {:.2}", delta);
        println!(
            "control signal: {:.2} = {:.2} + {:.2} + {:.2}",
            control_signal,
            proportional_component,
            integration_component,
            differentiation_component
        );

        let new_feedback = PidFeedback {
            delta: finite_or_zero(delta),
            integration_component: finite_or_zero(integration_component),
        };
        (control_signal, new_feedback)
    }
}

#[derive(Default)]
struct PidFeedback {
    delta: f32,
    integration_component: f32,
}

fn sum_and_push_new(revolutions: &RefCell<impl RingBuffer<u32>>) -> u32 {
    let mut revolutions = revolutions.borrow_mut();
    let sum = revolutions.iter().sum();
    revolutions.push(0);
    sum
}

fn finite_or_zero(value: f32) -> f32 {
    if value.is_finite() {
        value
    } else {
        0.
    }
}

fn limit(signal: f32, min: f32, max: f32) -> f32 {
    if signal < LIMIT_MIN_DEADZONE {
        0.
    } else {
        (signal + min).clamp(min, max)
    }
}

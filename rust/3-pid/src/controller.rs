use anyhow::anyhow;
use ringbuffer::{AllocRingBuffer, RingBuffer};
use rppal::i2c::I2c;
use rppal::pwm::{self, Pwm};
use std::cell::SyncUnsafeCell;
use std::sync::Arc;
use std::time::Duration;
use std::u8;
use tokio_stream::StreamExt;
use tokio_timerfd::Interval;

use crate::memory;
use crate::perf;
use crate::registers::Registers;

const PWM_MIN: f32 = 0.2;
const PWM_MAX: f32 = 1.0;

const LIMIT_MIN_DEADZONE: f32 = 0.001;

pub struct ControllerOptions {
    /// Frequency of control phase, during which the following happens:
    /// * calculating the frequency for the current time window,
    /// * moving the time window forward,
    /// * updating duty cycle,
    /// * updating modbus registers.
    pub control_frequency: u32,
    /// Frequency is estimated for the current time window. That window is broken into
    /// [time_window_bins] bins and is moved every time the control phase takes place.
    pub time_window_bins: usize,
    /// Each bin in the time window gets [reads_per_bin] reads, before the next control phase
    /// fires. That means, that the read phase occurs with frequency equal to:
    ///     `control_frequency * reads_per_bin`
    /// , because every time the window moves (control phase), there must be [reads_per_bin] reads
    /// in the last bin already (read phase).
    pub reads_per_bin: u32,
    /// When ADC reads below this signal, the state is set to `close` to the motor magnet. If the
    /// state has changed, a new revolution is counted.
    pub revolution_threshold_close: f32,
    /// When ADC reads above this signal, the state is set to `far` from the motor magnet.
    pub revolution_threshold_far: f32,
    /// Linux PWM channel to use.
    pub pwm_channel: pwm::Channel,
    /// Frequency of the PWM signal.
    pub pwm_frequency: f64,
}

pub struct Controller {
    options: ControllerOptions,
    registers: Arc<SyncUnsafeCell<Registers>>,
    pwm: Pwm,
    i2c: I2c,
    pwm_period: Duration,
    interval_rotate_once_s: f32,
    interval_rotate_all_s: f32,
    revolutions: AllocRingBuffer<u32>,
    is_close: bool,
    feedback: Feedback,
}

impl Controller {
    pub fn new(
        options: ControllerOptions,
        state: Arc<SyncUnsafeCell<Registers>>,
    ) -> anyhow::Result<Self> {
        let mut i2c = I2c::new()?;
        i2c.set_slave_address(0x48)?;

        let pwm = Pwm::new(options.pwm_channel)?;
        pwm.set_frequency(options.pwm_frequency, 0.)?;
        let pwm_period = pwm.period()?;
        pwm.enable()?;

        let mut revolutions = AllocRingBuffer::<u32>::new(options.time_window_bins);
        revolutions.fill_default();

        let interval_rotate_once_s: f32 = 1. / options.control_frequency as f32;
        let interval_rotate_all_s: f32 = interval_rotate_once_s * options.time_window_bins as f32;

        Ok(Self {
            options,
            registers: state,
            pwm,
            i2c,
            is_close: false,
            pwm_period,
            interval_rotate_once_s,
            interval_rotate_all_s,
            revolutions,
            feedback: Feedback::default(),
        })
    }

    pub async fn run(&mut self) -> anyhow::Result<!> {
        let read_frequency = self.options.control_frequency * self.options.reads_per_bin;
        let read_interval = Duration::SECOND / read_frequency;
        let mut interval = Interval::new_interval(read_interval)?;

        let perf_read_size = read_frequency as usize * 2;
        let perf_control_size = self.options.control_frequency as usize * 2;
        let mut perf_read = perf::Counter::new("READ", perf_read_size)?;
        let mut perf_control = perf::Counter::new("CONTROL", perf_control_size)?;

        let mut report_number: u64 = 0;
        while let Some(_) = interval.next().await {
            for _ in 0..self.options.control_frequency {
                for _ in 0..self.options.reads_per_bin {
                    let _read_measure = perf_read.measure();

                    if let Err(err) = self.read_phase() {
                        eprintln!("Controller::read_phase fail: {}", err);
                    }
                }

                let _control_measure = perf_control.measure();

                if let Err(err) = self.control_phase() {
                    eprintln!("Controller::control_phase fail: {}", err);
                }
            }

            println!("# REPORT {report_number}");
            memory::report();
            perf_read.report();
            perf_control.report();
            perf_read.reset();
            perf_control.reset();
            report_number += 1;
        }
        unreachable!("Interval stream is infinite");
    }

    fn read_phase(&mut self) -> anyhow::Result<()> {
        let value = self.read_adc()?;

        if value < self.options.revolution_threshold_close && !self.is_close {
            // gone close
            self.is_close = true;
            let back = self
                .revolutions
                .back_mut()
                .ok_or(anyhow!("Revolutions empty"))?;
            *back += 1;
        } else if value > self.options.revolution_threshold_far && self.is_close {
            // gone far
            self.is_close = false;
        }

        Ok(())
    }

    fn read_adc(&mut self) -> anyhow::Result<f32> {
        const WRITE_BUFFER: [u8; 1] = [adc_read_command(0)];
        let mut read_buffer = [0];

        self.i2c.write_read(&WRITE_BUFFER, &mut read_buffer)?;
        let value = read_buffer[0];
        let normalized = value as f32 / u8::MAX as f32;
        Ok(normalized)
    }

    fn control_phase(&mut self) -> anyhow::Result<()> {
        let frequency = self.calculate_frequency();
        self.revolutions.push(0);

        #[cfg(debug_assertions)]
        println!("frequency: {}", frequency);

        let registers = unsafe { self.registers.get().as_ref_unchecked() };
        let params = ControlParams::read(registers);

        let (control_signal, feedback) = self.calculate_control(&params, frequency, &self.feedback);

        let control_signal_limited = limit(control_signal, PWM_MIN, PWM_MAX);
        #[cfg(debug_assertions)]
        println!("control_signal_limited: {:.2}", control_signal_limited);
        self.write_registers(frequency, control_signal_limited);

        self.update_duty_cycle(control_signal_limited)?;
        self.feedback = feedback;

        Ok(())
    }

    fn calculate_frequency(&self) -> f32 {
        let sum: u32 = self.revolutions.iter().sum();
        sum as f32 / self.interval_rotate_all_s
    }

    fn calculate_control(
        &self,
        params: &ControlParams,
        frequency: f32,
        feedback: &Feedback,
    ) -> (f32, Feedback) {
        let delta = params.target_frequency - frequency;

        let integration_factor =
            params.proportional_factor / params.integration_time * self.interval_rotate_once_s;
        let differentiation_factor =
            params.proportional_factor * params.differentiation_time / self.interval_rotate_once_s;

        let proportional_component = params.proportional_factor * delta;
        let integration_component =
            feedback.integration_component + integration_factor * feedback.delta;
        let differentiation_component = differentiation_factor * (delta - feedback.delta);

        let control_signal =
            proportional_component + integration_component + differentiation_component;

        #[cfg(debug_assertions)]
        println!("delta: {:.2}", delta);
        #[cfg(debug_assertions)]
        println!(
            "control signal: {:.2} = {:.2} + {:.2} + {:.2}",
            control_signal,
            proportional_component,
            integration_component,
            differentiation_component
        );

        let new_feedback = Feedback {
            delta: finite_or_zero(delta),
            integration_component: finite_or_zero(integration_component),
        };
        (control_signal, new_feedback)
    }

    fn write_registers(&mut self, frequency: f32, control_signal_limited: f32) {
        let registers = unsafe { self.registers.get().as_mut_unchecked() };
        registers.write_input(.., [frequency, control_signal_limited]);
    }

    fn update_duty_cycle(&self, value: f32) -> anyhow::Result<()> {
        let pulse_width = self.pwm_period.mul_f32(value);
        self.pwm.set_pulse_width(pulse_width)?;
        Ok(())
    }
}

struct ControlParams {
    target_frequency: f32,
    proportional_factor: f32,
    integration_time: f32,
    differentiation_time: f32,
}

impl ControlParams {
    fn read(registers: &Registers) -> Self {
        let read_registers = registers.read_holding(..);

        #[rustfmt::skip]
        let &[
            target_frequency,
            proportional_factor,
            integration_time,
            differentiation_time
        ] = read_registers else { panic!("expected to read 4 registers") };

        Self {
            target_frequency,
            proportional_factor,
            integration_time,
            differentiation_time,
        }
    }
}

#[derive(Default)]
struct Feedback {
    delta: f32,
    integration_component: f32,
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

const fn adc_read_command(channel: u8) -> u8 {
    assert!(channel < 8);

    // bit    7: single-ended inputs mode
    // bits 6-4: channel selection
    // bit    3: is internal reference enabled
    // bit    2: is converter enabled
    // bits 1-0: unused
    const DEFAULT_READ_COMMAND: u8 = 0b10001100;

    DEFAULT_READ_COMMAND & (channel << 4)
}

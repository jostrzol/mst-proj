use std::num::NonZeroU32;
use std::pin::Pin;

use esp_idf_hal::adc::oneshot::config::Calibration;
use esp_idf_hal::adc::Adc;
use esp_idf_hal::delay;
use esp_idf_hal::gpio::{ADCPin, OutputPin};
use esp_idf_hal::ledc::{self, LedcDriver, LedcTimerDriver};
use esp_idf_hal::ledc::{LedcChannel, LedcTimer};
use esp_idf_hal::peripheral::Peripheral;
use esp_idf_hal::task::notification::Notification;
use esp_idf_hal::timer::{self, Timer, TimerDriver};
use esp_idf_hal::{
    adc::{
        self, attenuation,
        oneshot::{config::AdcChannelConfig, AdcChannelDriver, AdcDriver},
    },
    units::FromValueType,
};

use log::{error, info};
use ouroboros::self_referencing;
use ringbuffer::{AllocRingBuffer, RingBuffer};

use crate::registers::{HoldingRegister, InputRegister, Registers};

type LedcTimerConfig = ledc::config::TimerConfig;
type TimerConfig = timer::config::Config;

const ADC_BITWIDTH: u16 = 9;
const ADC_MAX_VALUE: u16 = (1 << ADC_BITWIDTH) - 1;

const PWM_FREQUENCY: u32 = 1000;
const PWM_MIN: f32 = 0.10;
const PWM_MAX: f32 = 1.00;

const LIMIT_MIN_DEADZONE: f32 = 0.001;

#[self_referencing]
pub struct ControllerHal<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    adc: AdcDriver<'a, TAdc>,
    #[borrows(adc)]
    #[covariant]
    adc_channel: AdcChannelDriver<'a, TAdcPin, &'this AdcDriver<'a, TAdc>>,
    ledc: LedcDriver<'a>,
    timer: TimerDriver<'a>,
}

pub struct ControllerOpts {
    pub frequency: u64,
    pub revolution_treshold_close: f32,
    pub revolution_treshold_far: f32,
    pub revolution_bins: usize,
    pub reads_per_bin: usize,
}

pub struct Controller<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    hal: ControllerHal<'a, TAdc, TAdcPin>,
    registers: Pin<&'a mut Registers>,
    notification: Notification,
    ledc_max_duty: u32,
    interval_rotate_once_s: f32,
    interval_rotate_all_s: f32,
    revolutions: AllocRingBuffer<u32>,
    is_close: bool,
    feedback: Feedback,
    opts: ControllerOpts,
}

impl<'a, TAdc, TAdcPin> Drop for Controller<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    fn drop(&mut self) {
        self.hal
            .with_timer_mut(|timer| timer.unsubscribe().expect("Cannot unsubscribe"));
    }
}

impl<'a, TAdc, TAdcPin> Controller<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    pub fn new<TLedcPin, TLedcChannel, TLedcTimer, TTimer>(
        adc: impl Peripheral<P = TAdc> + 'a,
        adc_pin: impl Peripheral<P = TAdcPin> + 'a,
        ledc_timer: impl Peripheral<P = TLedcTimer> + 'a,
        ledc_pin: impl Peripheral<P = TLedcPin> + 'a,
        ledc_channel: impl Peripheral<P = TLedcChannel> + 'a,
        timer: impl Peripheral<P = TTimer> + 'a,
        registers: Pin<&'a mut Registers>,
        opts: ControllerOpts,
    ) -> anyhow::Result<Self>
    where
        TLedcTimer: LedcTimer + 'a,
        TLedcPin: OutputPin,
        TLedcChannel: LedcChannel<SpeedMode = TLedcTimer::SpeedMode>,
        TTimer: Timer,
    {
        let adc_driver = AdcDriver::new(adc)?;
        let adc_config = AdcChannelConfig {
            attenuation: attenuation::DB_11,
            resolution: adc::Resolution::Resolution9Bit,
            calibration: Calibration::None,
        };

        let ledc_timer_config = LedcTimerConfig::new().frequency(PWM_FREQUENCY.Hz());
        let ledc_timer_driver = LedcTimerDriver::new(ledc_timer, &ledc_timer_config)?;
        let ledc_driver = LedcDriver::new(ledc_channel, ledc_timer_driver, ledc_pin)?;
        let ledc_max_duty = ledc_driver.get_max_duty();

        let timer_config = TimerConfig::new().auto_reload(true);
        let mut timer_driver = TimerDriver::new(timer, &timer_config)?;

        timer_driver.set_alarm(timer_driver.tick_hz() / opts.frequency)?;
        let notification = Notification::new();
        let notifier = notification.notifier();
        // Safety: make sure the `Notification` object is not dropped while the subscription is active
        unsafe {
            timer_driver.subscribe(move || {
                notifier.notify_and_yield(NonZeroU32::new(1).unwrap());
            })?;
        }
        timer_driver.enable_interrupt()?;
        timer_driver.enable_alarm(true)?;

        let hal = ControllerHalTryBuilder {
            adc: adc_driver,
            adc_channel_builder: move |adc| AdcChannelDriver::new(&adc, adc_pin, &adc_config),
            ledc: ledc_driver,
            timer: timer_driver,
        }
        .try_build()?;

        let mut revolutions = AllocRingBuffer::<u32>::new(opts.revolution_bins);
        revolutions.fill_default();

        let interval_rotate_once_s: f32 = 1. / opts.frequency as f32 * opts.reads_per_bin as f32;
        let interval_rotate_all_s: f32 = interval_rotate_once_s * opts.revolution_bins as f32;

        Ok(Self {
            hal,
            registers,
            notification,
            ledc_max_duty,
            interval_rotate_once_s,
            interval_rotate_all_s,
            revolutions,
            is_close: false,
            feedback: Feedback::default(),
            opts,
        })
    }

    pub fn run(&mut self) -> anyhow::Result<()> {
        self.hal.with_timer_mut(|timer| timer.enable(true))?;

        loop {
            for _ in 0..self.opts.reads_per_bin {
                while let None = self.notification.wait(delay::BLOCK) {}

                if let Err(err) = self.read_phase() {
                    error!("Error while running controller read phase: {}", err);
                }
            }
            if let Err(err) = self.control_phase() {
                error!("Error while running controller control phase: {}", err);
            }
        }
    }

    pub fn read_phase(&mut self) -> anyhow::Result<()> {
        let value = self.read_adc()?;

        if value < self.opts.revolution_treshold_close && !self.is_close {
            // gone close
            self.is_close = true;
            *self.revolutions.back_mut().expect("Revolutions empty") += 1;
        } else if value > self.opts.revolution_treshold_far && self.is_close {
            // gone far
            self.is_close = false;
        }

        Ok(())
    }

    fn read_adc(&mut self) -> Result<f32, anyhow::Error> {
        let value = self.hal.with_adc_channel_mut(|adc| adc.read_raw())?;
        Ok(value as f32 / ADC_MAX_VALUE as f32)
    }

    pub fn control_phase(&mut self) -> anyhow::Result<()> {
        let frequency = self.calculate_frequency();
        self.revolutions.push(0);

        info!("frequency: {}", frequency);

        let params = ControlParams::read(self.registers.as_ref());

        info!("target frequency: {:.2}", params.target_frequency,);

        let (control_signal, feedback) = self.calculate_control(&params, frequency, &self.feedback);

        let control_signal_limited = limit(control_signal, PWM_MIN, PWM_MAX);
        info!("control_signal_limited: {:.2}", control_signal_limited);
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

        info!("delta: {:.2}", delta);
        info!(
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

    fn write_registers(&mut self, frequency: f32, control_signal: f32) {
        use InputRegister::*;
        for (register, value) in [(Frequency, frequency), (ControlSignal, control_signal)] {
            self.registers.as_mut().write_input(register, value);
        }
    }

    fn update_duty_cycle(&mut self, value: f32) -> Result<(), anyhow::Error> {
        let duty_cycle = value * self.ledc_max_duty as f32;
        self.hal
            .with_ledc_mut(|ledc| ledc.set_duty(duty_cycle as u32))?;
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
    fn read(registers: Pin<&Registers>) -> Self {
        use HoldingRegister::*;
        Self {
            target_frequency: registers.read_holding(TargetFrequency),
            proportional_factor: registers.read_holding(ProportionalFactor),
            integration_time: registers.read_holding(IntegrationTime),
            differentiation_time: registers.read_holding(DifferentiationTime),
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

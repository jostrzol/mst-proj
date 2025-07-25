#![feature(asm_experimental_arch)]
#![feature(vec_push_within_capacity)]

mod memory;
mod perf;

use esp_idf_hal::adc::oneshot::config::Calibration;
use esp_idf_hal::delay::Delay;
use esp_idf_hal::ledc::{config::TimerConfig, LedcDriver, LedcTimerDriver};
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::{
    adc::{
        self, attenuation,
        oneshot::{config::AdcChannelConfig, AdcChannelDriver, AdcDriver},
    },
    units::FromValueType,
};
#[cfg(debug_assertions)]
use log::debug;
use log::info;
use memory::memory_report;

const ADC_BITWIDTH: u16 = 9;
const ADC_MAX_VALUE: u16 = (1 << ADC_BITWIDTH) - 1;

const PWM_FREQUENCY: u32 = 1000;

const CONTROL_FREQUENCY: u32 = 10;
const SLEEP_DURATION_MS: u32 = 1000 / CONTROL_FREQUENCY;

fn main() -> anyhow::Result<()> {
    esp_idf_hal::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    log::info!("Controlling motor from Rust");

    let peripherals = Peripherals::take()?;

    let adc = AdcDriver::new(peripherals.adc1)?;
    let adc_config = AdcChannelConfig {
        attenuation: attenuation::DB_11,
        resolution: adc::Resolution::Resolution9Bit,
        calibration: Calibration::None,
    };
    let mut adc_pin = AdcChannelDriver::new(&adc, peripherals.pins.gpio32, &adc_config)?;

    let timer_driver = LedcTimerDriver::new(
        peripherals.ledc.timer0,
        &TimerConfig::default().frequency(PWM_FREQUENCY.Hz()),
    )?;
    let mut driver = LedcDriver::new(
        peripherals.ledc.channel0,
        timer_driver,
        peripherals.pins.gpio5,
    )?;
    let max_duty_cycle = driver.get_max_duty();

    let delay = Delay::default();

    let mut perf = perf::Counter::new("MAIN", CONTROL_FREQUENCY as usize * 2)?;
    let mut report_number: u64 = 0;
    loop {
        for _ in 0..CONTROL_FREQUENCY {
            delay.delay_ms(SLEEP_DURATION_MS);

            let _measure = perf.measure();

            let value = match adc.read_raw(&mut adc_pin) {
                Ok(value) => value,
                Err(err) => {
                    eprintln!("AdcDriver::read_raw fail: {}", err);
                    continue;
                },
            };
            let value_normalized = value as f32 / ADC_MAX_VALUE as f32;
            #[cfg(debug_assertions)]
            debug!(
                "selected duty cycle: {:.2} = {} / {}",
                value_normalized, value, ADC_MAX_VALUE
            );

            let duty_cycle = value_normalized * max_duty_cycle as f32;
            if let Err(err) = driver.set_duty(duty_cycle as u32) {
                eprintln!("LedcDriver::set_duty fail: {}", err);
                continue;
            };
        }

        info!("# REPORT {report_number}");
        memory_report();
        perf.report();
        perf.reset();
        report_number += 1;
    }
}

#![feature(asm_experimental_arch)]

mod memory;
mod perf;

use esp_idf_hal::adc::oneshot::config::Calibration;
use esp_idf_hal::delay::Delay;
use esp_idf_hal::ledc::{config::TimerConfig, LedcDriver, LedcTimerDriver};
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::sys::xTaskGetCurrentTaskHandle;
use esp_idf_hal::{
    adc::{
        self, attenuation,
        oneshot::{config::AdcChannelConfig, AdcChannelDriver, AdcDriver},
    },
    units::FromValueType,
};
use log::debug;
use memory::memory_report;

const SLEEP_DURATION_MS: u32 = 100;
const CONTROL_ITERS_PER_PERF_REPORT: usize = 10;

const ADC_BITWIDTH: u16 = 9;
const ADC_MAX_VALUE: u16 = (1 << ADC_BITWIDTH) - 1;

const PWM_FREQUENCY: u32 = 1000;

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
    let task = unsafe { xTaskGetCurrentTaskHandle() };
    let mut perf = perf::Counter::new("MAIN")?;

    loop {
        for _ in 0..CONTROL_ITERS_PER_PERF_REPORT {
            delay.delay_ms(SLEEP_DURATION_MS);

            let _measure = perf.measure();

            let value = adc.read_raw(&mut adc_pin)?;
            let value_normalized = value as f32 / ADC_MAX_VALUE as f32;
            debug!(
                "selected duty cycle: {:.2} = {} / {}",
                value_normalized, value, ADC_MAX_VALUE
            );

            let duty_cycle = value_normalized * max_duty_cycle as f32;
            if let Err(err) = driver.set_duty(duty_cycle as u32) {
                eprintln!("Setting duty cycle: {}", err)
            };
        }
        memory_report(&[task]);
        perf.report();
        perf.reset();
    }
}

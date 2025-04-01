use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::{
    adc::{
        self,
        attenuation::DB_11,
        oneshot::{config::AdcChannelConfig, AdcChannelDriver, AdcDriver},
    },
    delay::Delay,
};

const FREQUENCY: u32 = 100;
const SLEEP_DURATION_MS: u32 = 1000 / FREQUENCY;

const ADC_BITWIDTH: u8 = 9;
const ADC_MAX_VALUE: u16 = (1 << ADC_BITWIDTH) - 1;

fn main() -> anyhow::Result<()> {
    esp_idf_hal::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    log::info!("Controlling motor from Rust");

    let peripherals = Peripherals::take()?;

    let adc = AdcDriver::new(peripherals.adc1)?;

    let adc_config = AdcChannelConfig {
        attenuation: DB_11,
        resolution: adc::Resolution::Resolution9Bit,
        ..Default::default()
    };
    let mut adc_pin = AdcChannelDriver::new(&adc, peripherals.pins.gpio32, &adc_config)?;

    let delay = Delay::default();
    loop {
        let value = adc.read(&mut adc_pin)?;
        println!("value: {}", value);

        delay.delay_ms(SLEEP_DURATION_MS);
    }
}

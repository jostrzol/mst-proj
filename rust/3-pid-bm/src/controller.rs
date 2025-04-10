use anyhow::anyhow;
use esp_idf_hal::adc::oneshot::config::Calibration;
use esp_idf_hal::adc::Adc;
use esp_idf_hal::gpio::{ADCPin, OutputPin};
use esp_idf_hal::ledc::{config::TimerConfig, LedcDriver, LedcTimerDriver};
use esp_idf_hal::ledc::{LedcChannel, LedcTimer};
use esp_idf_hal::peripheral::{Peripheral, PeripheralRef};
use esp_idf_hal::{
    adc::{
        self, attenuation,
        oneshot::{config::AdcChannelConfig, AdcChannelDriver, AdcDriver},
    },
    units::FromValueType,
};

use log::{error, info};

const FREQUENCY: u64 = 100;
const SLEEP_DURATION_MS: u64 = 1000 / FREQUENCY;

const ADC_BITWIDTH: u16 = 9;
const ADC_MAX_VALUE: u16 = (1 << ADC_BITWIDTH) - 1;
const ADC_CONFIG: AdcChannelConfig = AdcChannelConfig {
    attenuation: attenuation::DB_11,
    resolution: adc::Resolution::Resolution9Bit,
    calibration: Calibration::None,
};

const PWM_FREQUENCY: u32 = 1000;

macro_rules! trylbl {
    ($label:tt, $expr:expr) => {
        match $expr {
            Ok(res) => res,
            Err(err) => break $label Err(err.into()),
        }
    };
}

pub struct Controller<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    adc_driver: AdcDriver<'a, TAdc>,
    adc_pin: Option<PeripheralRef<'a, TAdcPin>>,
    ledc_driver: LedcDriver<'a>,
    ledc_max_duty: u32,
}

impl<'a, TAdc, TAdcPin> Controller<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    pub fn new<TLedcPin, TLedcChannel, TLedcTimer>(
        adc: impl Peripheral<P = TAdc> + 'a,
        adc_pin: impl Peripheral<P = TAdcPin> + 'a,
        ledc_timer: impl Peripheral<P = TLedcTimer> + 'a,
        ledc_pin: impl Peripheral<P = TLedcPin> + 'a,
        ledc_channel: impl Peripheral<P = TLedcChannel> + 'a,
    ) -> anyhow::Result<Self>
    where
        TLedcTimer: LedcTimer + 'a,
        TLedcPin: OutputPin,
        TLedcChannel: LedcChannel<SpeedMode = TLedcTimer::SpeedMode>,
    {
        let adc_driver = AdcDriver::new(adc)?;

        let ledc_timer_driver = LedcTimerDriver::new(
            ledc_timer,
            &TimerConfig::default().frequency(PWM_FREQUENCY.Hz()),
        )?;
        let ledc_driver = LedcDriver::new(ledc_channel, ledc_timer_driver, ledc_pin)?;
        let ledc_max_duty = ledc_driver.get_max_duty();

        Ok(Self {
            adc_driver,
            adc_pin: Some(adc_pin.into_ref()),
            ledc_driver,
            ledc_max_duty,
        })
    }

    pub fn run(&mut self) -> anyhow::Result<()> {
        let adc_pin = self
            .adc_pin
            .take()
            .ok_or(anyhow!("Cannot execute Controller::run twice"))?;

        let mut adc_channel_driver = AdcChannelDriver::new(&self.adc_driver, adc_pin, &ADC_CONFIG)?;

        loop {
            let iteration_result: anyhow::Result<()> = 'blk: {
                let value = trylbl!('blk, Self::read_adc(&mut adc_channel_driver));

                info!("selected duty cycle: {}", value);

                let duty_cycle = value * self.ledc_max_duty as f32;
                trylbl!('blk, self.ledc_driver.set_duty(duty_cycle as u32));

                Ok(())
            };

            if let Err(err) = iteration_result {
                error!("Error while running controller loop iteration: {}", err);
            }

            std::thread::sleep(core::time::Duration::from_millis(SLEEP_DURATION_MS));
        }
    }

    pub fn read_adc<'b>(
        adc_channel_driver: &mut AdcChannelDriver<'a, TAdcPin, &'b AdcDriver<'a, TAdc>>,
    ) -> anyhow::Result<f32> {
        let value = adc_channel_driver.read_raw()?;
        Ok(value as f32 / ADC_MAX_VALUE as f32)
    }
}

use esp_idf_hal::adc::oneshot::config::Calibration;
use esp_idf_hal::adc::Adc;
use esp_idf_hal::gpio::{ADCPin, OutputPin};
use esp_idf_hal::ledc::{config::TimerConfig, LedcDriver, LedcTimerDriver};
use esp_idf_hal::ledc::{LedcChannel, LedcTimer};
use esp_idf_hal::peripheral::Peripheral;
use esp_idf_hal::{
    adc::{
        self, attenuation,
        oneshot::{config::AdcChannelConfig, AdcChannelDriver, AdcDriver},
    },
    units::FromValueType,
};

use log::{error, info};
use ouroboros::self_referencing;

const FREQUENCY: u64 = 100;
const SLEEP_DURATION_MS: u64 = 1000 / FREQUENCY;

const ADC_BITWIDTH: u16 = 9;
const ADC_MAX_VALUE: u16 = (1 << ADC_BITWIDTH) - 1;

const PWM_FREQUENCY: u32 = 1000;

#[self_referencing]
pub struct ControllerHal<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    adc_driver: AdcDriver<'a, TAdc>,
    #[borrows(adc_driver)]
    #[covariant]
    adc_channel_driver: AdcChannelDriver<'a, TAdcPin, &'this AdcDriver<'a, TAdc>>,
    ledc_driver: LedcDriver<'a>,
}

pub struct Controller<'a, TAdc, TAdcPin>
where
    TAdc: Adc,
    TAdcPin: ADCPin<Adc = TAdc>,
{
    hal: ControllerHal<'a, TAdc, TAdcPin>,
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
        let adc_config = AdcChannelConfig {
            attenuation: attenuation::DB_11,
            resolution: adc::Resolution::Resolution9Bit,
            calibration: Calibration::None,
        };

        let ledc_timer_driver = LedcTimerDriver::new(
            ledc_timer,
            &TimerConfig::default().frequency(PWM_FREQUENCY.Hz()),
        )?;
        let ledc_driver = LedcDriver::new(ledc_channel, ledc_timer_driver, ledc_pin)?;
        let ledc_max_duty = ledc_driver.get_max_duty();

        let hal = ControllerHalTryBuilder {
            adc_driver,
            adc_channel_driver_builder: move |adc_driver| {
                AdcChannelDriver::new(&adc_driver, adc_pin, &adc_config)
            },
            ledc_driver,
        }
        .try_build()?;

        Ok(Self { hal, ledc_max_duty })
    }

    pub fn run(&mut self) {
        loop {
            if let Err(err) = self.iteration() {
                error!("Error while running controller loop iteration: {}", err);
            }

            std::thread::sleep(core::time::Duration::from_millis(SLEEP_DURATION_MS));
        }
    }

    pub fn iteration(&mut self) -> anyhow::Result<()> {
        let value = self.read_adc()?;
        info!("selected duty cycle: {:.2}", value);

        let duty_cycle = value * self.ledc_max_duty as f32;
        self.update_duty_cycle(duty_cycle)?;

        Ok(())
    }

    fn read_adc(&mut self) -> Result<f32, anyhow::Error> {
        let value = self
            .hal
            .with_adc_channel_driver_mut(|mut adc| adc.read_raw())?;
        Ok(value as f32 / ADC_MAX_VALUE as f32)
    }

    fn update_duty_cycle(&mut self, duty_cycle: f32) -> Result<(), anyhow::Error> {
        self.hal
            .with_ledc_driver_mut(|ledc| ledc.set_duty(duty_cycle as u32))?;
        Ok(())
    }
}

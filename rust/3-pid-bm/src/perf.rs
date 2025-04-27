use core::arch::asm;
use esp_idf_sys::{
    esp, esp_clk_tree_src_get_freq_hz, esp_cpu_cycle_count_t, soc_module_clk_t_SOC_MOD_CLK_CPU,
};
use log::info;
use std::mem::MaybeUninit;

pub struct Measurement<'a> {
    counter: &'a mut Counter,
    start: esp_cpu_cycle_count_t,
}

impl Drop for Measurement<'_> {
    fn drop(&mut self) {
        self.counter.add_sample(self.start);
    }
}

pub struct Counter {
    name: &'static str,
    cpu_frequency: u32,
    total_cycles: esp_cpu_cycle_count_t,
    sample_count: u32,
}

impl Counter {
    pub fn new(name: &'static str) -> anyhow::Result<Self> {
        let mut cpu_frequency = MaybeUninit::uninit();
        esp!(unsafe {
            esp_clk_tree_src_get_freq_hz(
                soc_module_clk_t_SOC_MOD_CLK_CPU,
                0,
                cpu_frequency.as_mut_ptr(),
            )
        })?;

        Ok(Counter {
            name,
            cpu_frequency: unsafe { cpu_frequency.assume_init() },
            total_cycles: 0,
            sample_count: 0,
        })
    }

    pub fn measure(&mut self) -> Measurement {
        Measurement {
            counter: self,
            start: esp_cpu_get_cycle_count(),
        }
    }

    fn add_sample(&mut self, start: esp_cpu_cycle_count_t) {
        let end = esp_cpu_get_cycle_count();
        let cycles = end - start;

        self.total_cycles += cycles;
        self.sample_count += 1;
    }

    pub fn report(&self) {
        let cycles_avg = self.total_cycles as f64 / self.sample_count as f64;
        let time_us = cycles_avg / self.cpu_frequency as f64 * 1e6;

        info!(
            "Performance counter {}: {:.3} us = {:.0} cycles ({} sampl.)",
            self.name, time_us, cycles_avg, self.sample_count
        );
    }

    pub fn reset(&mut self) {
        self.total_cycles = 0;
        self.sample_count = 0;
    }
}

macro_rules! rsr {
    ($reg:expr) => {{
        let result: u32;
        asm! {
            "rsr {ret}, {reg}",
            ret = out(reg) result,
            reg = const $reg,
        }
        result
    }};
}

#[inline]
fn esp_cpu_get_cycle_count() -> u32 {
    unsafe { rsr!(234) }
}

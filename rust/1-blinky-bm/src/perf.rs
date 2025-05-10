use core::arch::asm;
use esp_idf_sys::{
    esp, esp_clk_tree_src_get_freq_hz, esp_cpu_cycle_count_t, soc_module_clk_t_SOC_MOD_CLK_CPU,
};
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
    samples: Vec<esp_cpu_cycle_count_t>,
}

impl Counter {
    pub fn new(name: &'static str, length: usize) -> anyhow::Result<Self> {
        let mut cpu_frequency = MaybeUninit::uninit();
        esp!(unsafe {
            esp_clk_tree_src_get_freq_hz(
                soc_module_clk_t_SOC_MOD_CLK_CPU,
                0,
                cpu_frequency.as_mut_ptr(),
            )
        })?;

        let samples = Vec::with_capacity(length);

        Ok(Counter {
            name,
            cpu_frequency: unsafe { cpu_frequency.assume_init() },
            samples,
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
        let diff = (end - start) as u32;

        if let Err(err) = self.samples.push_within_capacity(diff) {
            eprintln!("perf::Counter::add_sample: {err}");
        }
    }

    pub fn report(&self) {
        print!("Performance counter {}: [", self.name);
        for (i, sample) in self.samples.iter().enumerate() {
            let value = *sample as f32 * 1e6 / self.cpu_frequency as f32;
            print!("{:.2}", value);
            if i < self.samples.len() - 1 {
                print!(",");
            }
        }
        println!("] us");
    }

    pub fn reset(&mut self) {
        self.samples.clear();
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

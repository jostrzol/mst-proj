use std::mem::variant_count;

use num_derive::ToPrimitive;
use num_traits::ToPrimitive;

#[derive(PartialOrd, Ord, PartialEq, Eq, Clone, Copy, ToPrimitive)]
pub enum InputRegister {
    Frequency,
    ControlSignal,
}

#[derive(PartialOrd, Ord, PartialEq, Eq, Clone, Copy, ToPrimitive)]
pub enum HoldingRegister {
    TargetFrequency,
    ProportionalFactor,
    IntegrationTime,
    DifferentiationTime,
}

#[repr(C)]
pub struct Registers {
    pub input: [f32; variant_count::<InputRegister>()],
    pub holding: [f32; variant_count::<HoldingRegister>()],
}

impl Registers {
    pub fn new() -> Self {
        Self {
            input: Default::default(),
            holding: [0., 0., f32::INFINITY, 0.],
        }
    }

    pub fn read_input(&self, register: InputRegister) -> f32 {
        self.input[register.to_usize().unwrap()]
    }

    pub fn write_input(&mut self, register: InputRegister, value: f32) {
        self.input[register.to_usize().unwrap()] = value;
    }

    pub fn read_holding(&self, register: HoldingRegister) -> f32 {
        self.holding[register.to_usize().unwrap()]
    }

    pub fn write_holding(&mut self, register: HoldingRegister, value: f32) {
        self.holding[register.to_usize().unwrap()] = value;
    }
}

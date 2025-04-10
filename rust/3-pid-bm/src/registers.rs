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
#[derive(Default, Clone, Copy)]
pub struct FloatCDAB {
    raw: [u8; 4],
}

impl From<FloatCDAB> for f32 {
    fn from(val: FloatCDAB) -> Self {
        let [c, d, a, b] = val.raw;
        Self::from_be_bytes([a, b, c, d])
    }
}

impl From<f32> for FloatCDAB {
    fn from(value: f32) -> Self {
        let [a, b, c, d]: [u8; 4] = value.to_be_bytes();
        FloatCDAB { raw: [c, d, a, b] }
    }
}

#[repr(C)]
pub struct Registers {
    pub input: [FloatCDAB; variant_count::<InputRegister>()],
    pub holding: [FloatCDAB; variant_count::<HoldingRegister>()],
}

impl Registers {
    pub fn new() -> Self {
        Self {
            input: Default::default(),
            holding: [
                Default::default(),
                Default::default(),
                f32::INFINITY.into(),
                Default::default(),
            ],
        }
    }

    pub fn read_input(&self, register: InputRegister) -> f32 {
        self.input[register.to_usize().unwrap()].into()
    }

    pub fn write_input(&mut self, register: InputRegister, value: f32) {
        self.input[register.to_usize().unwrap()] = value.into();
    }

    pub fn read_holding(&self, register: HoldingRegister) -> f32 {
        self.holding[register.to_usize().unwrap()].into()
    }

    pub fn write_holding(&mut self, register: HoldingRegister, value: f32) {
        self.holding[register.to_usize().unwrap()] = value.into()
    }
}

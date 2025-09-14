use std::{marker::PhantomPinned, mem::variant_count, pin::Pin};

use num_derive::ToPrimitive;
use num_traits::ToPrimitive;

#[derive(PartialOrd, Ord, PartialEq, Eq, Clone, Copy, ToPrimitive)]
pub enum InputRegister {
    Frequency,
    ControlSignal,
    ValueMin,
    ValueMax,
}

#[derive(PartialOrd, Ord, PartialEq, Eq, Clone, Copy, ToPrimitive)]
pub enum HoldingRegister {
    ControlSignal,
    ThresholdClose,
    ThresholdFar,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
pub struct FloatCDAB {
    raw: [u8; 4],
}

impl From<FloatCDAB> for f32 {
    fn from(val: FloatCDAB) -> Self {
        let [c, d, a, b] = val.raw;
        Self::from_le_bytes([a, b, c, d])
    }
}

impl From<f32> for FloatCDAB {
    fn from(value: f32) -> Self {
        let [a, b, c, d]: [u8; 4] = value.to_le_bytes();
        FloatCDAB { raw: [c, d, a, b] }
    }
}

#[repr(C)]
pub struct Registers {
    pub input: [FloatCDAB; variant_count::<InputRegister>()],
    pub holding: [FloatCDAB; variant_count::<HoldingRegister>()],
    _pin: PhantomPinned,
}

impl Registers {
    pub fn new() -> Self {
        Self {
            input: Default::default(),
            holding: Default::default(),
            _pin: PhantomPinned {},
        }
    }

    pub fn write_input(self: Pin<&mut Self>, register: InputRegister, value: f32) {
        let this = unsafe { self.get_unchecked_mut() };
        this.input[register.to_usize().unwrap()] = value.into();
    }

    pub fn read_holding(self: Pin<&Self>, register: HoldingRegister) -> f32 {
        self.holding[register.to_usize().unwrap()].into()
    }
}

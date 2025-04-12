use std::{marker::PhantomPinned, mem::variant_count, pin::Pin};

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
    _pin: PhantomPinned,
}

impl Registers {
    pub fn new() -> Self {
        Self {
            input: Default::default(),
            holding: [0., 0., f32::INFINITY, 0.],
            _pin: PhantomPinned {},
        }
    }

    pub fn write_input(self: Pin<&mut Self>, register: InputRegister, value: f32) {
        let this = unsafe { self.get_unchecked_mut() };
        this.input[register.to_usize().unwrap()] = value;
    }

    pub fn read_holding(self: Pin<&Self>, register: HoldingRegister) -> f32 {
        self.holding[register.to_usize().unwrap()]
    }
}

use std::{
    mem::variant_count,
    ops::{Bound, IntoBounds},
};

use num_derive::{FromPrimitive, ToPrimitive};
use num_traits::{FromPrimitive, ToPrimitive};

#[derive(PartialOrd, Ord, PartialEq, Eq, Clone, Copy, FromPrimitive, ToPrimitive)]
pub enum InputRegister {
    Frequency,
    ControlSignal,
}

#[derive(PartialOrd, Ord, PartialEq, Eq, Clone, Copy, FromPrimitive, ToPrimitive)]
pub enum HoldingRegister {
    TargetFrequency,
    ProportionalFactor,
    IntegrationTime,
    DifferentiationTime,
}

pub struct Registers {
    input: [f32; variant_count::<InputRegister>()],
    holding: [f32; variant_count::<HoldingRegister>()],
}

impl Registers {
    pub fn new() -> Self {
        Self {
            input: Default::default(),
            holding: [0., 0., f32::INFINITY, 0.],
        }
    }

    pub fn read_input_registers(&self, range: impl IntoBounds<InputRegister>) -> &[f32] {
        &self.input[into_usize_bounds(range)]
    }

    pub fn write_input_registers(
        &mut self,
        range: impl IntoBounds<InputRegister>,
        values: impl IntoIterator<Item = f32>,
    ) {
        self.input[into_usize_bounds(range)]
            .iter_mut()
            .zip(values)
            .for_each(|(reg, value)| *reg = value);
    }

    pub fn read_holding_registers(&self, range: impl IntoBounds<HoldingRegister>) -> &[f32] {
        &self.holding[into_usize_bounds(range)]
    }

    pub fn write_holding_registers(
        &mut self,
        range: impl IntoBounds<HoldingRegister>,
        values: impl IntoIterator<Item = f32>,
    ) {
        self.holding[into_usize_bounds(range)]
            .iter_mut()
            .zip(values)
            .for_each(|(reg, value)| *reg = value);
    }
}

fn into_usize_bounds<T>(range: impl IntoBounds<T>) -> (Bound<usize>, Bound<usize>)
where
    T: ToPrimitive,
{
    let (start, end) = range.into_bounds();
    let start = start.map(|x| x.to_usize().unwrap());
    let end = end.map(|x| x.to_usize().unwrap());
    (start, end)
}

pub fn range_from_addr_count<T>(addr: u16, count: u16) -> Option<impl IntoBounds<T>>
where
    T: FromPrimitive,
{
    let start = T::from_u16(addr)?;
    let end = T::from_u16(addr + count - 1)?;
    Some(start..=end)
}

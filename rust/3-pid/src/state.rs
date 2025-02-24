use std::mem::variant_count;

use ringbuffer::{ConstGenericRingBuffer, RingBuffer};

#[allow(dead_code)]
pub enum InputRegister {
    Frequency,
    ControlValue,
}

#[allow(dead_code)]
pub enum HoldingRegister {
    TargetFrequency,
    ProportionalFactor,
    IntegrationTime,
    Differentiationtime,
}

pub struct State<const CAP: usize> {
    readings: ConstGenericRingBuffer<u16, CAP>,
    input_registers: [f32; variant_count::<InputRegister>()],
    holding_registers: [f32; variant_count::<HoldingRegister>()],
}

impl<const CAP: usize> State<CAP> {
    pub fn new() -> Self {
        Self {
            readings: Default::default(),
            input_registers: Default::default(),
            holding_registers: [0., 0., f32::INFINITY, 0.],
        }
    }

    pub fn push(&mut self, value: u8) {
        self.readings.push(value.into());
    }

    pub fn get_readings(&mut self, count: usize) -> Vec<u16> {
        let mut result = self.readings.to_vec();
        self.readings.clear();

        match count.cmp(&result.len()) {
            std::cmp::Ordering::Less => {
                result.drain(count..result.len());
                result
            }
            std::cmp::Ordering::Equal => result,
            std::cmp::Ordering::Greater => {
                let missing = count - result.len();
                [result, vec![u16::MAX; missing]].concat()
            }
        }
    }

    pub fn read_input_registers(&self, addr: usize, count: usize) -> &[f32] {
        &self.input_registers[addr..count]
    }

    pub fn write_input_registers(&mut self, addr: usize, values: impl IntoIterator<Item = f32>) {
        self.input_registers[addr..]
            .iter_mut()
            .zip(values)
            .for_each(|(reg, value)| *reg = value);
    }

    pub fn read_holding_registers(&self, addr: usize, count: usize) -> &[f32] {
        &self.holding_registers[addr..count]
    }

    pub fn write_holding_registers(&mut self, addr: usize, values: impl IntoIterator<Item = f32>) {
        self.holding_registers[addr..]
            .iter_mut()
            .zip(values)
            .for_each(|(reg, value)| *reg = value);
    }
}

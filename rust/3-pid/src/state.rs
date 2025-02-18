use ringbuffer::{ConstGenericRingBuffer, RingBuffer};
use std::{ops::Deref, time::Instant};

pub struct State<const CAP: usize> {
    head_id: u16,
    readings: ConstGenericRingBuffer<u16, CAP>,
    set_value: u8,
}

impl<const CAP: usize> State<CAP> {
    pub fn new() -> Self {
        Self {
            head_id: 0,
            readings: Default::default(),
            set_value: Default::default(),
        }
    }

    pub async fn push(&mut self, value: u8) {
        self.readings.push(value.into());
    }

    pub async fn readings(&self, id: u8) -> Vec<Reading> {
        let tail_id = self.head_id - self.readings.le
        let readings = self.readings.lock().await;
        let index_first = Self::binsearch_after(readings.deref(), delta_time_ms);

        let mut result = Vec::with_capacity(readings.len() - index_first);
        for i in index_first..readings.len() {
            result.push(readings[i]);
        }
        result
    }
}

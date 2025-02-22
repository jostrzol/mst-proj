use ringbuffer::{ConstGenericRingBuffer, RingBuffer};

pub struct State<const CAP: usize> {
    readings: ConstGenericRingBuffer<u16, CAP>,
    current: u16,
    target: u16,
}

impl<const CAP: usize> State<CAP> {
    pub fn new() -> Self {
        Self {
            readings: Default::default(),
            target: Default::default(),
            current: Default::default(),
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

    pub fn set_target(&mut self, value: u16) {
        self.target = value;
    }

    pub fn get_target(&mut self) -> f64 {
        self.target as f64 / u16::MAX as f64
    }

    pub fn set_current(&mut self, value: u16) {
        self.current = value;
    }

    pub fn get_current(&mut self) -> u16 {
        self.current
    }
}

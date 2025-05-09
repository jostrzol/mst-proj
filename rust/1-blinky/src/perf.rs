use std::{ffi::c_int, io, mem::MaybeUninit};

pub struct Measurement<'a> {
    counter: &'a mut Counter,
    start: u64,
}

impl Drop for Measurement<'_> {
    fn drop(&mut self) {
        self.counter.add_sample(self.start);
    }
}

pub struct Counter {
    name: &'static str,
    total_time_ns: u64,
    sample_count: u32,
}

impl Counter {
    pub fn new(name: &'static str) -> Result<Self, io::Error> {
        let mut resolution = MaybeUninit::uninit();
        let res = unsafe { clock_getres(Clock::ThreadCputime, resolution.as_mut_ptr()) };
        if res != 0 {
            return Err(io::Error::from_raw_os_error(res));
        }

        println!(
            "Performance counter {}, resolution: {} ns",
            name,
            unsafe { resolution.assume_init() }.to_ns()
        );

        Ok(Counter {
            name,
            total_time_ns: 0,
            sample_count: 0,
        })
    }

    pub fn measure(&mut self) -> Measurement {
        Measurement {
            counter: self,
            start: Timespec::now().to_ns(),
        }
    }

    fn add_sample(&mut self, start_ns: u64) {
        let end = Timespec::now().to_ns();
        let diff = end - start_ns;

        self.total_time_ns += diff;
        self.sample_count += 1;
    }

    pub fn report(&self) {
        let time_us = self.total_time_ns as f64 / self.sample_count as f64 / 1000.0;

        println!(
            "Performance counter {}: {:.3} us ({} sampl.)",
            self.name, time_us, self.sample_count
        );
    }

    pub fn reset(&mut self) {
        self.total_time_ns = 0;
        self.sample_count = 0;
    }
}

#[repr(C)]
struct Timespec {
    tv_sec: u32,
    tv_nsec: u32,
}

impl Timespec {
    pub fn now() -> Self {
        let mut time = MaybeUninit::uninit();
        let res = unsafe { clock_gettime(Clock::ThreadCputime, time.as_mut_ptr()) };

        if res != 0 {
            Timespec {
                tv_sec: 0,
                tv_nsec: 0,
            }
        } else {
            unsafe { time.assume_init() }
        }
    }
    pub fn to_ns(&self) -> u64 {
        self.tv_nsec as u64 + self.tv_sec as u64 * 1_000_000_000
    }
}

#[allow(dead_code)]
#[repr(u32)]
enum Clock {
    Realtime = 0,
    Monotonic = 1,
    ProcessCputime = 2,
    ThreadCputime = 3,
    MonotonicRaw = 4,
    RealtimeCoarse = 5,
    MonotonicCoarse = 6,
    Boottime = 7,
    RealtimeAlarm = 8,
    BoottimeAlarm = 9,
    Tai = 11,
}

extern "C" {
    fn clock_getres(clock_id: Clock, timespec: *mut Timespec) -> c_int;
    fn clock_gettime(clock_id: Clock, timespec: *mut Timespec) -> c_int;
}

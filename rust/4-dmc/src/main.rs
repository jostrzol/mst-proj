#![feature(duration_constants)]
#![feature(impl_trait_in_assoc_type)]
#![feature(variant_count)]
#![feature(iter_array_chunks)]
#![feature(range_into_bounds)]

mod controller;
mod server;
mod state;

use std::{sync::Arc, time::Duration};

use async_mutex::Mutex;
use controller::{run_controller, ControllerSettings};
use rppal::pwm;
use server::serve;
use state::State;
use tokio::signal::ctrl_c;

const READ_RATE: u128 = 1000;
const READ_INTERVAL: Duration =
    Duration::from_nanos((Duration::SECOND.as_nanos() / READ_RATE) as u64);

const CONTROLLER_SETTINGS: ControllerSettings = ControllerSettings {
    read_interval: READ_INTERVAL,
    revolution_treshold_close: 105,
    revolution_treshold_far: 118,
    revolution_bins: 10,
    control_interval: Duration::from_millis(100),
    pwm_channel: pwm::Channel::Pwm1,
    pwm_frequency: 1000.,
};

// #[tokio::main]
// async fn main() -> Result<(), Box<dyn std::error::Error>> {
//     let state = Arc::new(Mutex::new(State::new()));
//     let socket_addr = "0.0.0.0:5502".parse()?;
//
//     tokio::select! {
//         result = serve(socket_addr, state.clone()) => match result {
//             Ok(_) => unreachable!(),
//             err => err,
//         },
//         result = run_controller(CONTROLLER_SETTINGS, state) => match result {
//             Ok(_) => unreachable!(),
//             err => err,
//         },
//         result = ctrl_c() => match result {
//             Ok(_) => {
//                 println!("Gracefully stopping\n");
//                 Ok(())
//             },
//             Err(err) => Err(err.into()),
//         },
//     }
// }

use nalgebra::{DMatrix, DVector};

pub struct DMC {
    pub prediction_horizon: usize,
    pub control_horizon: usize,
    pub lambda: f32,
    pub previous_inputs: Vec<f32>,
    pub previous_outputs: Vec<f32>,
    pub g_matrix: DMatrix<f32>,
    pub g_matrix_t: DMatrix<f32>,
}

impl DMC {
    pub fn new(
        step_response: &[f32],
        prediction_horizon: usize,
        control_horizon: usize,
        lambda: f32,
    ) -> Self {
        let previous_inputs = vec![0.0; control_horizon];
        let previous_outputs = vec![0.0; prediction_horizon];
        let g_matrix =
            Self::construct_g_matrix(&step_response, prediction_horizon, control_horizon);
        let g_matrix_t = g_matrix.transpose();
        DMC {
            prediction_horizon,
            control_horizon,
            lambda,
            previous_inputs,
            previous_outputs,
            g_matrix,
            g_matrix_t,
        }
    }

    pub fn compute_control(&mut self, setpoint: f32, current_output: f32) -> f32 {
        let error = setpoint - current_output;

        let identity = DMatrix::<f32>::identity(self.control_horizon, self.control_horizon);
        let lambda_matrix = self.lambda * identity;

        let inverse_term = (self.g_matrix_t.clone() * &self.g_matrix + lambda_matrix)
            .try_inverse()
            .unwrap();
        let k_matrix = inverse_term * &self.g_matrix_t;

        let error_vector = DVector::from_vec(vec![error; self.prediction_horizon]);
        let delta_u = k_matrix * error_vector;

        let control_signal = delta_u[0];
        self.previous_inputs.insert(0, control_signal);
        self.previous_inputs.pop();

        control_signal
    }

    fn construct_g_matrix(
        step_response: &[f32],
        prediction_horizon: usize,
        control_horizon: usize,
    ) -> DMatrix<f32> {
        let mut g_matrix = DMatrix::<f32>::zeros(prediction_horizon, control_horizon);
        for i in 0..prediction_horizon {
            for j in 0..control_horizon {
                if i >= j {
                    g_matrix[(i, j)] = step_response[i - j];
                }
            }
        }
        g_matrix
    }
}

fn main() {
    let step_response = [0.1, 0.2, 0.4, 0.6, 0.8, 1.0];
    let mut dmc = DMC::new(&step_response, 6, 3, 0.1);

    let setpoint = 1.0;
    let mut current_output = 0.0;

    for _ in 0..10 {
        let control_signal = dmc.compute_control(setpoint, current_output);
        println!("Control Signal: {}", control_signal);
        current_output += control_signal * 0.5;
        println!("Current Output: {}", current_output);
    }
}

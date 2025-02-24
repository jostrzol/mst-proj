// SPDX-FileCopyrightText: Copyright (c) 2017-2024 slowtec GmbH <post@slowtec.de>
// SPDX-License-Identifier: MIT OR Apache-2.0

//! # TCP server example
//!
//! This example shows how to start a server and implement basic register
//! read/write operations.

use std::{error::Error, future::Future, net::SocketAddr, sync::Arc};

use async_mutex::Mutex;
use tokio::net::TcpListener;

use tokio_modbus::{
    prelude::*,
    server::{
        tcp::{accept_tcp_connection, Server},
        Service,
    },
};

use crate::state::State;

struct PidService<const CAP: usize> {
    state: Arc<Mutex<State<CAP>>>,
}

impl<const CAP: usize> Service for PidService<CAP> {
    type Request = Request<'static>;
    type Response = Response;
    type Exception = ExceptionCode;
    type Future = impl Future<Output = Result<Self::Response, Self::Exception>>;

    fn call(&self, req: Self::Request) -> Self::Future {
        let state = self.state.clone();
        async move {
            match req {
                Request::ReadInputRegisters(addr, count) => {
                    let state = state.lock().await;
                    let floats = state.read_input_registers(addr as usize, count as usize);
                    let data: Vec<_> = floats
                        .iter()
                        .flat_map(|x| x.to_be_bytes())
                        .array_chunks()
                        .map(u16::from_be_bytes)
                        .collect();
                    Ok(Response::ReadInputRegisters(data))
                }
                Request::WriteMultipleRegisters(addr, values) => {
                    let mut state = state.lock().await;
                    let bytes: Vec<_> = values.iter().flat_map(|x| x.to_be_bytes()).collect();
                    print!("receiving {:x?}", bytes);
                    let floats: Vec<_> = bytes
                        .into_iter()
                        .array_chunks()
                        .map(f32::from_be_bytes)
                        .collect();
                    println!(" = {:?}", floats);
                    state.write_holding_registers(addr as usize, floats);
                    Ok(Response::WriteMultipleRegisters(addr, values.len() as u16))
                }
                _ => Err(ExceptionCode::IllegalFunction),
            }
        }
    }
}

impl<const CAP: usize> PidService<CAP> {
    fn new(state: Arc<Mutex<State<CAP>>>) -> Self {
        Self { state }
    }
}

pub async fn serve<const CAP: usize>(
    state: Arc<Mutex<State<CAP>>>,
    socket_addr: SocketAddr,
) -> Result<(), Box<dyn Error>> {
    println!("Starting up server on {socket_addr}");
    let listener = TcpListener::bind(socket_addr).await?;
    let server = Server::new(listener);
    let new_service = |_socket_addr| Ok(Some(PidService::new(state.clone())));
    let on_connected = |stream, socket_addr| async move {
        accept_tcp_connection(stream, socket_addr, new_service)
    };
    let on_process_error = |err| {
        eprintln!("{err}");
    };
    server.serve(&on_connected, on_process_error).await?;
    Ok(())
}

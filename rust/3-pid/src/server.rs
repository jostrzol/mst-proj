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

use crate::state::{range_from_addr_count, State};

struct PidService {
    state: Arc<Mutex<State>>,
}

impl Service for PidService {
    type Request = Request<'static>;
    type Response = Response;
    type Exception = ExceptionCode;
    type Future = impl Future<Output = Result<Self::Response, Self::Exception>>;

    fn call(&self, req: Self::Request) -> Self::Future {
        let state = self.state.clone();
        async move {
            match req {
                Request::ReadInputRegisters(addr, count) => {
                    if count % 2 != 0 {
                        return Err(ExceptionCode::IllegalDataAddress);
                    }
                    let range = range_from_addr_count(addr, count / 2)
                        .ok_or(ExceptionCode::IllegalDataAddress)?;

                    let state = state.lock().await;
                    let floats = state.read_input_registers(range);
                    let data: Vec<_> = floats
                        .iter()
                        .flat_map(|x| x.to_be_bytes())
                        .array_chunks()
                        .map(u16::from_be_bytes)
                        .collect();
                    Ok(Response::ReadInputRegisters(data))
                }
                Request::WriteMultipleRegisters(addr, values) => {
                    if values.len() % 2 != 0 {
                        return Err(ExceptionCode::IllegalDataValue);
                    }

                    let bytes = values.iter().flat_map(|x| x.to_be_bytes());
                    let floats: Vec<_> = bytes.array_chunks().map(f32::from_be_bytes).collect();

                    let range = range_from_addr_count(addr, floats.len() as u16)
                        .ok_or(ExceptionCode::IllegalDataAddress)?;

                    let mut state = state.lock().await;
                    state.write_holding_registers(range, floats);
                    Ok(Response::WriteMultipleRegisters(addr, values.len() as u16))
                }
                _ => Err(ExceptionCode::IllegalFunction),
            }
        }
    }
}

impl PidService {
    fn new(state: Arc<Mutex<State>>) -> Self {
        Self { state }
    }
}

pub async fn serve(
    socket_addr: SocketAddr,
    state: Arc<Mutex<State>>,
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

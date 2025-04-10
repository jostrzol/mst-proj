use std::ffi::c_void;
use std::mem::MaybeUninit;
use std::ptr;

use esp_idf_svc::netif::EspNetif;
use esp_idf_sys::esp;
use esp_idf_sys::modbus::{
    mb_communication_info_t, mb_communication_info_t__bindgen_ty_2, mb_mode_type_t_MB_MODE_TCP,
    mb_param_type_t_MB_PARAM_HOLDING, mb_param_type_t_MB_PARAM_INPUT,
    mb_register_area_descriptor_t, mb_tcp_addr_type_t_MB_IPV4, mbc_slave_destroy,
    mbc_slave_init_tcp, mbc_slave_set_descriptor, mbc_slave_setup, mbc_slave_start,
};
use log::info;

use crate::registers::Registers;

const SERVER_PORT_NUMBER: u16 = 5502;
const SERVER_MODBUS_ADDRESS: u8 = 0;

pub struct Server {
    #[allow(dead_code)]
    handle: *mut c_void,
}

impl Drop for Server {
    fn drop(&mut self) {
        Self::close();
    }
}

impl Server {
    pub fn new(netif: &EspNetif, registers: &Registers) -> anyhow::Result<Server> {
        let mut maybe_handle = MaybeUninit::<*mut c_void>::uninit();
        esp!(unsafe { mbc_slave_init_tcp(maybe_handle.as_mut_ptr()) })?;
        let handle = unsafe { maybe_handle.assume_init() };

        let comm_info = mb_communication_info_t {
            __bindgen_anon_2: mb_communication_info_t__bindgen_ty_2 {
                ip_mode: mb_mode_type_t_MB_MODE_TCP,
                slave_uid: SERVER_MODBUS_ADDRESS,
                ip_port: SERVER_PORT_NUMBER,
                ip_addr_type: mb_tcp_addr_type_t_MB_IPV4,
                ip_addr: ptr::null_mut(),
                ip_netif_ptr: netif as *const EspNetif as *mut c_void,
            },
        };
        let comm_info_ptr = &comm_info as *const mb_communication_info_t as *mut c_void;
        esp!(unsafe { mbc_slave_setup(comm_info_ptr) }).inspect_err(|_| Self::close())?;

        let input_registers = mb_register_area_descriptor_t {
            type_: mb_param_type_t_MB_PARAM_INPUT,
            size: size_of_val(&registers.input),
            address: &registers.input as *const [_] as *mut c_void,
            start_offset: 0,
        };
        esp!(unsafe { mbc_slave_set_descriptor(input_registers) })
            .inspect_err(|_| Self::close())?;

        let holding_registers = mb_register_area_descriptor_t {
            type_: mb_param_type_t_MB_PARAM_HOLDING,
            size: size_of_val(&registers.holding),
            address: &registers.holding as *const [_] as *mut c_void,
            start_offset: 0,
        };
        esp!(unsafe { mbc_slave_set_descriptor(holding_registers) })
            .inspect_err(|_| Self::close())?;

        esp!(unsafe { mbc_slave_start() }).inspect_err(|_| Self::close())?;

        info!("Modbus server listening for requests");

        Ok(Server { handle })
    }

    fn close() {
        info!("Closing modbus server");
        unsafe { mbc_slave_destroy() };
    }
}

use std::ffi::c_void;
use std::mem::MaybeUninit;
use std::ptr;

use esp_idf_svc::netif::EspNetif;
use esp_idf_sys::esp;
use esp_idf_sys::modbus::{
    mb_communication_info_t, mb_communication_info_t__bindgen_ty_2,
    mb_event_group_t_MB_EVENT_COILS_RD, mb_event_group_t_MB_EVENT_COILS_WR,
    mb_event_group_t_MB_EVENT_DISCRETE_RD, mb_event_group_t_MB_EVENT_HOLDING_REG_RD,
    mb_event_group_t_MB_EVENT_HOLDING_REG_WR, mb_event_group_t_MB_EVENT_INPUT_REG_RD,
    mb_mode_type_t_MB_MODE_TCP, mb_param_info_t, mb_param_type_t_MB_PARAM_HOLDING,
    mb_param_type_t_MB_PARAM_INPUT, mb_register_area_descriptor_t, mb_tcp_addr_type_t_MB_IPV4,
    mbc_slave_check_event, mbc_slave_destroy, mbc_slave_get_param_info, mbc_slave_init_tcp,
    mbc_slave_set_descriptor, mbc_slave_setup, mbc_slave_start,
};
use log::{error, info};

use crate::registers::Registers;

const SERVER_PORT_NUMBER: u16 = 5502;
const SERVER_MODBUS_ADDRESS: u8 = 0;

const SERVER_PAR_INFO_GET_TOUT_MS: u32 = 10; // Timeout for get parameter info

const MB_READ_MASK: u32 = mb_event_group_t_MB_EVENT_INPUT_REG_RD
    | mb_event_group_t_MB_EVENT_HOLDING_REG_RD
    | mb_event_group_t_MB_EVENT_DISCRETE_RD
    | mb_event_group_t_MB_EVENT_COILS_RD;
const MB_WRITE_MASK: u32 =
    mb_event_group_t_MB_EVENT_HOLDING_REG_WR | mb_event_group_t_MB_EVENT_COILS_WR;
const MB_READ_WRITE_MASK: u32 = MB_READ_MASK | MB_WRITE_MASK;

const MB_HOLDING_MASK: u32 =
    mb_event_group_t_MB_EVENT_HOLDING_REG_WR | mb_event_group_t_MB_EVENT_HOLDING_REG_RD;
const MB_INPUT_MASK: u32 = mb_event_group_t_MB_EVENT_INPUT_REG_RD;

pub struct Server {}

impl Drop for Server {
    fn drop(&mut self) {
        Self::close();
    }
}

impl Server {
    pub fn new(netif: &EspNetif, registers: &Registers) -> anyhow::Result<Server> {
        let mut handle = MaybeUninit::uninit();
        esp!(unsafe { mbc_slave_init_tcp(handle.as_mut_ptr()) })?;

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

        Ok(Server {})
    }

    pub fn run(&self) {
        info!("Listening for modbus requests...");

        loop {
            if let Err(err) = self.handle_request() {
                error!("Error while handling modbus request: {}", err);
            }
        }
    }

    fn handle_request(&self) -> anyhow::Result<()> {
        unsafe { mbc_slave_check_event(MB_READ_WRITE_MASK) };

        let reg_info = self.get_param_info()?;

        if reg_info.type_ & MB_READ_MASK != 0 {
            return Ok(()); // Don't log reads
        }

        let rw_str = if reg_info.type_ & MB_READ_MASK != 0 {
            "READ"
        } else {
            "WRITE"
        };

        let type_str = if reg_info.type_ & MB_HOLDING_MASK != 0 {
            "HOLDING"
        } else if reg_info.type_ & MB_INPUT_MASK != 0 {
            "INPUT"
        } else {
            "UNKNOWN"
        };

        info!(
            "{} {} ({} us) ADDR:{}, TYPE:{}, INST_ADDR:{:X}, SIZE:{}",
            type_str,
            rw_str,
            reg_info.time_stamp,
            reg_info.mb_offset,
            reg_info.type_,
            unsafe { *reg_info.address },
            reg_info.size
        );

        Ok(())
    }

    fn get_param_info(&self) -> anyhow::Result<mb_param_info_t> {
        let mut reg_info = MaybeUninit::<mb_param_info_t>::uninit();
        esp!(unsafe {
            mbc_slave_get_param_info(reg_info.as_mut_ptr(), SERVER_PAR_INFO_GET_TOUT_MS)
        })?;
        Ok(unsafe { reg_info.assume_init() })
    }

    fn close() {
        info!("Closing modbus server");
        unsafe { mbc_slave_destroy() };
    }
}

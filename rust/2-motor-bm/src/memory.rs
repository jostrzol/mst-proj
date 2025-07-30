use std::{ffi::CStr, mem::MaybeUninit};

use esp_idf_sys::{
    heap_caps_get_free_size, heap_caps_get_total_size, pcTaskGetName, vTaskGetSnapshot,
    xTaskGetCurrentTaskHandle, TaskHandle_t,
};
use log::{error, info};

pub fn memory_report() {
    let task = unsafe { xTaskGetCurrentTaskHandle() };
    let name = unsafe {
        let name = pcTaskGetName(task.clone());
        CStr::from_ptr(name).to_string_lossy()
    };

    let Some(stack_usage) = stack_usage(task.clone()) else {
        error!("stack_usage fail");
        return;
    };

    info!("{} stack usage: {} B", name, stack_usage);

    let total_heap_size = unsafe { heap_caps_get_total_size(0) };
    let free_heap_size = unsafe { heap_caps_get_free_size(0) };
    let heap_usage = total_heap_size - free_heap_size;
    info!("Heap usage: {} B", heap_usage);
}

fn stack_usage(task: TaskHandle_t) -> Option<isize> {
    let mut snapshot = MaybeUninit::uninit();
    let ret = unsafe { vTaskGetSnapshot(task, snapshot.as_mut_ptr()) };
    if ret != 1 {
        return None;
    };
    let snapshot = unsafe { snapshot.assume_init() };

    let usage = unsafe { snapshot.pxEndOfStack.offset_from(snapshot.pxTopOfStack) };
    return Some(usage);
}

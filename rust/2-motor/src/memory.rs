use std::{cell::SyncUnsafeCell, ffi::c_void};

static HEAP_USAGE: SyncUnsafeCell<usize> = SyncUnsafeCell::new(0);

pub fn report() {
    unsafe {
        let heap_usage = *HEAP_USAGE.get();
        println!("Heap usage: {heap_usage} B");
    }
}

extern "C" {
    fn malloc_usable_size(ptr: *mut c_void) -> usize;
    fn __libc_malloc(size: usize) -> *mut c_void;
    fn __libc_calloc(count: usize, size: usize) -> *mut c_void;
    fn __libc_realloc(ptr: *mut c_void, size: usize) -> *mut c_void;
    fn __libc_free(ptr: *mut c_void);
}

#[no_mangle]
pub unsafe extern "C" fn malloc(size: usize) -> *mut c_void {
    let ptr = __libc_malloc(size);
    *HEAP_USAGE.get() += malloc_usable_size(ptr);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn calloc(count: usize, size: usize) -> *mut c_void {
    let ptr = __libc_calloc(count, size);
    *HEAP_USAGE.get() += malloc_usable_size(ptr);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn realloc(ptr: *mut c_void, size: usize) -> *mut c_void {
    let old_size = malloc_usable_size(ptr);
    let new_ptr = __libc_realloc(ptr, size);
    *HEAP_USAGE.get() += malloc_usable_size(new_ptr) - old_size;
    new_ptr
}

#[no_mangle]
pub unsafe extern "C" fn free(ptr: *mut c_void) {
    *HEAP_USAGE.get() -= malloc_usable_size(ptr);
    __libc_free(ptr)
}

use std::ffi::c_void;

static mut HEAP_USAGE: usize = 0;

pub fn report() {
    unsafe {
        let heap_usage = &raw mut HEAP_USAGE;
        println!("Heap usage: {} B", *heap_usage);
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
    HEAP_USAGE += size;
    __libc_malloc(size)
}

#[no_mangle]
pub unsafe extern "C" fn calloc(count: usize, size: usize) -> *mut c_void {
    HEAP_USAGE += count * size;
    __libc_calloc(count, size)
}

#[no_mangle]
pub unsafe extern "C" fn realloc(ptr: *mut c_void, size: usize) -> *mut c_void {
    HEAP_USAGE += size - malloc_usable_size(ptr);
    __libc_realloc(ptr, size)
}

#[no_mangle]
pub unsafe extern "C" fn free(ptr: *mut c_void) {
    HEAP_USAGE -= malloc_usable_size(ptr);
    __libc_free(ptr)
}

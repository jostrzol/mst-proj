use std::{
    cell::SyncUnsafeCell,
    ffi::{c_int, c_void},
    mem::MaybeUninit,
};

static HEAP_USAGE: SyncUnsafeCell<usize> = SyncUnsafeCell::new(0);

pub fn report() {
    unsafe {
        let stack_frame: u8 = 0;

        let mut attr = MaybeUninit::uninit();
        _ = pthread_getattr_np(pthread_self(), attr.as_mut_ptr());
        let attr = attr.assume_init();

        let mut stack_addr = MaybeUninit::uninit();
        let mut stack_capcity = MaybeUninit::uninit();
        pthread_attr_getstack(
            &attr as *const PthreadAttr,
            stack_addr.as_mut_ptr(),
            stack_capcity.as_mut_ptr(),
        );

        let stack_end =
            (stack_addr.assume_init() as usize + stack_capcity.assume_init()) as *const c_void;
        let stack_pointer = &stack_frame as *const u8;
        let stack_size = stack_end as usize - stack_pointer as usize;
        println!("Stack usage: {stack_size} B");

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

    fn pthread_self() -> u32;
    fn pthread_getattr_np(pid: u32, pthread_attr: *mut PthreadAttr) -> c_int;
    fn pthread_attr_destroy(pthread_attr: *const PthreadAttr) -> c_int;
    fn pthread_attr_getstack(
        pthread_attr: *const PthreadAttr,
        stack_addr: *mut *const c_void,
        stack_size: *mut usize,
    ) -> c_int;
}

#[repr(C, align(8))]
struct PthreadAttr([u8; 56]);

impl Drop for PthreadAttr {
    fn drop(&mut self) {
        unsafe { pthread_attr_destroy(self as *const Self) };
    }
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

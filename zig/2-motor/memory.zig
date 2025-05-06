const std = @import("std");

const c = @import("c.zig");

var heap_usage: usize = 0;

pub fn report() void {
    var stack_frame: u8 = undefined;

    var attr: c.pthread_attr_t = undefined;
    _ = c.pthread_getattr_np(c.pthread_self(), &attr);
    defer _ = c.pthread_attr_destroy(&attr);

    var stack_addr: *void = undefined;
    var stack_capcity: usize = undefined;
    _ = c.pthread_attr_getstack(&attr, @ptrCast(&stack_addr), &stack_capcity);

    const stack_end: *void = @ptrFromInt(@intFromPtr(stack_addr) + stack_capcity);
    const stack_pointer = &stack_frame;
    const stack_size = @intFromPtr(stack_end) - @intFromPtr(stack_pointer);

    std.log.info("MAIN stack usage: {} B", .{stack_size});
    std.log.info("Heap usage: {} B", .{heap_usage});
}

pub extern "c" fn __libc_malloc(size: usize) *void;
pub extern "c" fn __libc_calloc(count: usize, size: usize) *void;
pub extern "c" fn __libc_realloc(ptr: *void, size: usize) *void;
pub extern "c" fn __libc_free(ptr: *void) void;

export fn malloc(size: usize) *void {
    const ptr = __libc_malloc(size);
    heap_usage += c.malloc_usable_size(ptr);
    return ptr;
}
export fn calloc(count: usize, size: usize) *void {
    const ptr = __libc_calloc(count, size);
    heap_usage += c.malloc_usable_size(ptr);
    return ptr;
}
export fn realloc(ptr: *void, size: usize) *void {
    const old_size = c.malloc_usable_size(ptr);
    const new_ptr = __libc_realloc(ptr, size);
    heap_usage += c.malloc_usable_size(new_ptr) - old_size;
    return new_ptr;
}
export fn free(ptr: *void) void {
    heap_usage -= c.malloc_usable_size(ptr);
    __libc_free(ptr);
}

pub const CountingAllocator = struct {
    child: std.mem.Allocator,

    const Self = @This();
    pub fn init(child: std.mem.Allocator) Self {
        return .{ .child = child };
    }
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = Self.alloc,
                .resize = Self.resize,
                .free = Self.free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        heap_usage += len;
        return self.child.rawAlloc(len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        heap_usage += new_len - buf.len;
        return self.child.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        heap_usage -= buf.len;
        return self.child.rawFree(buf, buf_align, ret_addr);
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn RingBuffer(comptime T: type) type {
    return struct {
        items: []T,
        tail: usize = 0,

        const Self = @This();

        pub fn init(allocator: Allocator, n: usize) !Self {
            const items = try allocator.alloc(T, n);
            @memset(items, 0);
            return .{ .items = items };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.items);
        }

        pub fn back(self: *Self) *T {
            return &self.items[self.tail];
        }

        pub fn push(self: *Self, item: T) !void {
            self.tail = (self.tail + 1) % self.items.len;
            self.items[self.tail] = item;
        }
    };
}

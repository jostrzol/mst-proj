const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const utils = @import("utils.zig");

pub fn report(tasks: []const sys.TaskHandle_t) void {
    for (tasks) |task| {
        const name = sys.pcTaskGetName(task);

        const task_stack_usage = stackUsage(task) catch |err| {
            std.log.err("Failed to get stack usage of task {s}: {}", .{ name, err });
            continue;
        };

        std.log.info("{s} stack usage: {} B", .{ name, task_stack_usage });
    }

    const total_heap_size = sys.heap_caps_get_total_size(0);
    const free_heap_size = sys.heap_caps_get_free_size(0);
    const heap_usage = total_heap_size - free_heap_size;
    std.log.info("Heap usage: {} B", .{heap_usage});
}

fn stackUsage(task: sys.TaskHandle_t) !u32 {
    var snapshot: sys.TaskSnapshot_t = undefined;
    try utils.rtosCheckError(sys.vTaskGetSnapshot(task, &snapshot));

    return snapshot.pxEndOfStack - snapshot.pxTopOfStack;
}

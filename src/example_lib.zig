const std = @import("std");
const bind = @import("bind_gen.zig");

pub const MyStruct = extern struct {
    a: i32,
    b: i32,

    pub fn __init__() callconv(.C) *MyStruct {
        const allocator = std.heap.page_allocator;
        const my_struct = allocator.create(MyStruct) catch unreachable;

        // give default values
        my_struct.* = MyStruct{
            .a = 42,
            .b = 84,
        };
        return my_struct;
    }

    pub fn __del__(ptr: *MyStruct) callconv(.C) void {
        const allocator = std.heap.page_allocator;
        allocator.destroy(ptr);
    }

    pub fn print(ptr: *MyStruct) callconv(.C) void {
        std.debug.print("from zig: {any}\n", .{ptr.*});
    }
};

comptime {
    bind.exportStruct(MyStruct);
}

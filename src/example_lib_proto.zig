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

    pub fn sum(ptr: *MyStruct) callconv(.C) i32 {
        return ptr.a + ptr.b;
    }

    pub fn update(ptr: *MyStruct, a: i32, b: i32) callconv(.C) void {
        ptr.a = a;
        ptr.b = b;
    }
};

comptime {
    bind.exportStruct(MyStruct);
}

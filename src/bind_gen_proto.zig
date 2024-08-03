const std = @import("std");
const print = std.debug.print;

const PyStringAlias: type = [*:0]u8;

const PyStringStruct = extern struct {
    value: [*:0]u8,
};

pub fn main() void {
    const test_arg = [_]type{ i32, i8, bool, [*:0]u8, PyStringStruct, PyStringAlias };

    inline for (test_arg) |arg| {
        // const type_info = @typeInfo(arg);
        print("arg {any}\n", .{arg});
    }
}

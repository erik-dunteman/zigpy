const std = @import("std");
const print = std.debug.print;
const templ = @import("./template.zig");

const targetStruct = @import("./example_lib.zig").MyStruct;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    comptime var split_itr = std.mem.splitBackwardsAny(u8, @typeName(targetStruct), ".");
    const struct_ident = comptime split_itr.first();

    var template_data = templ.TemplateData.init(alloc, struct_ident);

    const info = @typeInfo(targetStruct);
    std.debug.assert(info == .Struct);
    const struct_info = info.Struct;

    // add fields
    inline for (struct_info.fields) |field| {
        try template_data.addField(field.name, field.type);
    }

    // add methods
    var has_init = false;
    var has_del = false;
    inline for (struct_info.decls) |decl| {
        if (std.mem.eql(u8, decl.name, "__init__")) {
            // these are special methods with strict templating
            has_init = true;
        } else if (std.mem.eql(u8, decl.name, "__del__")) {
            // these are special methods with strict templating
            has_del = true;
        } else {
            // these are user-defined methods
            // start building up a MethodData
            const ident = decl.name;

            const user_fn = @field(targetStruct, decl.name);
            const user_fn_info = @typeInfo(@TypeOf(user_fn));
            std.debug.assert(user_fn_info == .Fn);
            if (user_fn_info.Fn.params.len == 0) {
                std.debug.print("Namespaced function {s} has no args, and will be skipped.\nAll bound functions must be methods with self as the first arg.\n", .{ident});
                comptime continue;
            }

            var method_data = try templ.MethodData.init(alloc, struct_ident, ident);
            try switch (user_fn_info.Fn.return_type.?) {
                *targetStruct => method_data.addSelfReturnType(true),
                targetStruct => method_data.addSelfReturnType(false),
                else => method_data.addReturnType(user_fn_info.Fn.return_type.?),
            };

            // "self" arg

            // regular args
            inline for (user_fn_info.Fn.params, 0..) |param, i| {
                if (i == 0) {
                    if (param.type.? != *targetStruct and param.type.? != targetStruct) {
                        @compileError("first method arg must be self");
                    }
                }

                const arg_ident = if (i > 0) std.fmt.comptimePrint("arg{}", .{i - 1}) else "self";
                switch (param.type.?) {
                    *targetStruct => try method_data.addSelfArg(arg_ident, true),
                    targetStruct => try method_data.addSelfArg(arg_ident, true),
                    else => try method_data.addArg(param.type.?, arg_ident),
                }
            }
            try template_data.addMethod(&method_data);
        }
    }

    const rendered = try template_data.render();

    const output_file_path = struct_ident ++ ".py";
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch unreachable;
    defer output_file.close();
    try output_file.writeAll(rendered);
}

/// For use by users to flag their structs for export
pub fn exportStruct(comptime zig_struct: type) void {
    const info = @typeInfo(zig_struct);
    switch (info) {
        .Struct => |struct_info| {
            inline for (struct_info.decls) |decl| {
                const field = @field(zig_struct, decl.name);
                @export(field, .{ .name = "codegenstruct_" ++ decl.name });
            }
        },
        else => @compileError("exportStruct only works with structs"),
    }
}

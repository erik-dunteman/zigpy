const std = @import("std");
const builtin = @import("builtin");
const mustache = @import("vendors/mustache-zig/src/mustache.zig");
const template = @import("./template.zig").get_template();

const wrapperType = union(enum) {
    methodArg,
    methodResult,
};

const wrappedResult = struct {
    nativeType: type,
    ctype: []const u8,
    ctype_to_py_fn: ?[]const u8,
};

const wrappedArg = struct {
    nativeType: type,
    identifier: []const u8,
    ctype: []const u8,
    py_to_ctype_fn: ?[]const u8,
};

fn wrapType(
    comptime T: type,
    comptime WT: wrapperType,
) type {
    switch (T) {
        i32 => {
            const ctype = "c_int";
            switch (WT) {
                .methodArg => return wrappedArg{
                    .identifier = "arg1",
                    .nativeType = T,
                    .ctype = ctype,
                    .py_to_ctype_fn = null,
                },
                .methodResult => return wrappedResult{
                    .nativeType = T,
                    .ctype = ctype,
                    .ctype_to_py_fn = null,
                },
                else => {},
            }
        },
        else => {},
    }
    return struct {};
}

// users should import their own library
// todo: autodetect this or do something tricky in build.zig
const targetStruct = @import("./example_lib.zig").MyStruct;

pub fn main() !void {
    comptime var split_itr = std.mem.splitBackwardsAny(u8, @typeName(targetStruct), ".");
    const struct_name = comptime split_itr.first();

    const shared_lib_extension = switch (builtin.os.tag) {
        .macos => "dylib",
        .linux => "so",
        else => @compileError("unsupported os"),
    };

    // assumptions
    // all pub structs are also "extern"
    // all relevant methods are "pub export" and within the namespace of the struct

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const info = @typeInfo(targetStruct); // todo: make CodeGenStruct dynamic and "addlib" dynamic
    switch (info) {
        .Struct => |struct_info| {
            const CTypeImport = struct { id: []const u8 };
            var c_type_import_data = std.ArrayList(CTypeImport).init(alloc);
            const Field = struct {
                name: []const u8,
                type: []const u8,
            };
            var field_data = std.ArrayList(Field).init(alloc);
            const Property = struct {
                name: []const u8,
            };
            var properties = std.ArrayList(Property).init(alloc);
            inline for (struct_info.fields) |field| {
                const type_id: []const u8 = "c_int";
                try field_data.append(.{ .name = field.name, .type = type_id }); // todo: make type dynamic
                var is_imported = false;
                for (c_type_import_data.items) |c_type_import| {
                    if (std.mem.eql(u8, c_type_import.id, type_id)) {
                        is_imported = true;
                        break;
                    }
                }
                if (!is_imported) {
                    try c_type_import_data.append(.{ .id = type_id });
                }
                try properties.append(.{ .name = field.name });
            }
            var init_data = std.ArrayList(u8).init(alloc);
            var del_data = std.ArrayList(u8).init(alloc);
            const Arg = struct {
                name: []const u8,
                pytype: []const u8,
                ctype: []const u8,
                conversion_func: []const u8,
            };
            const Method = struct {
                pyname: []const u8,
                zigname: []const u8,
                args: []Arg,
                res_ctype: []const u8,
                render_res_ctype: bool,
                res_conversion_func: []const u8, // for any extra conversion needed
            };
            var methods = std.ArrayList(Method).init(alloc);
            inline for (struct_info.decls) |decl| {
                if (std.mem.eql(u8, decl.name, "__init__")) {
                    try init_data.appendSlice("codegenstruct_" ++ decl.name); // todo: make lowercasing of codegenstruct dynamic
                } else if (std.mem.eql(u8, decl.name, "__del__")) {
                    try del_data.appendSlice("codegenstruct_" ++ decl.name);
                } else {
                    const zigname = "codegenstruct_" ++ decl.name; // in the shared library we prefix with the struct name to avoid collisions
                    var args_data = std.ArrayList(Arg).init(alloc);

                    // add args if relevant
                    const user_fn = @field(targetStruct, decl.name);
                    const user_fn_info = @typeInfo(@TypeOf(user_fn));
                    // it's a func
                    inline for (user_fn_info.Fn.params) |param| {
                        const wrapped = wrapType(param.type.?, wrapperType.methodArg);
                        @compileLog("wrapped", wrapped);
                        switch (param.type.?) {
                            *targetStruct => {
                                // we assume it's self here, ignore
                                // todo: in cases where another instance of the self type is passed in as a legitimate arg
                                // this would wrongly reject it
                            },
                            // string type
                            [*:0]u8 => {
                                const arg_name: []const u8 = "arg1"; // this is annoying, we can't use user's arg name
                                const ctype: []const u8 = "c_char_p";
                                try args_data.append(Arg{
                                    .name = arg_name, //todo: increment
                                    .pytype = "str",
                                    .ctype = ctype,
                                    .conversion_func = try mustache.allocRenderText(
                                        alloc,
                                        "{{name}}.encode('utf-8')",
                                        .{ .name = arg_name },
                                    ),
                                });
                                var is_imported = false;
                                for (c_type_import_data.items) |c_type_import| {
                                    if (std.mem.eql(u8, c_type_import.id, ctype)) {
                                        is_imported = true;
                                        break;
                                    }
                                }
                                if (!is_imported) {
                                    try c_type_import_data.append(.{ .id = ctype });
                                }
                            },
                            else => {
                                // this is annoying, because inline for this branch is executed even on
                                // the __init__ and __del__ cases so we can't compile error on unsupported arg types
                                @compileLog(param.type);
                                @compileError("unsupported argument type");
                            },
                        }
                    }

                    const maybe_res_ctype: ?[]const u8 = switch (user_fn_info.Fn.return_type.?) {
                        void => "c_void_p",
                        *targetStruct => null, // todo: if user returns a valid pointer, this would break
                        i32 => "c_int",
                        else => {
                            @compileLog(user_fn_info.Fn.return_type.?);
                            @compileError("unsupported return type");
                        },
                        [*:0]const u8 => "c_char_p",
                    };

                    // assure those types are imported
                    if (maybe_res_ctype) |res_ctype| {
                        var is_imported = false;
                        for (c_type_import_data.items) |c_type_import| {
                            if (std.mem.eql(u8, c_type_import.id, res_ctype)) {
                                is_imported = true;
                                break;
                            }
                        }
                        if (!is_imported) {
                            try c_type_import_data.append(.{ .id = res_ctype });
                        }
                    }

                    // render conversion function
                    const res_conversion_func = switch (user_fn_info.Fn.return_type orelse void) {
                        [*:0]const u8 => "c_res.decode('utf-8')",
                        else => "c_res",
                    };

                    try methods.append(.{
                        .pyname = decl.name,
                        .zigname = zigname,
                        .args = args_data.items,
                        .res_ctype = maybe_res_ctype orelse "",
                        .res_conversion_func = res_conversion_func,
                        .render_res_ctype = (maybe_res_ctype != null),
                    });
                }
            }
            const data = .{
                .struct_name = struct_name,
                .field_data = field_data.items,
                .properties = properties.items,
                .init = init_data.items,
                .del = del_data.items,
                .methods = methods.items,
                .shared_lib_extension = shared_lib_extension,
                .c_type_imports = c_type_import_data.items,
            };
            const result = try mustache.allocRenderText(alloc, template, data);

            const output_file_path = struct_name ++ ".py";
            var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch unreachable;
            defer output_file.close();
            try output_file.writeAll(result);
        },

        else => unreachable,
    }

    return std.process.cleanExit();
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

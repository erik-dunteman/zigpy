const std = @import("std");
const print = std.debug.print;
const templ = @import("./template_proto.zig");

const targetStruct = @import("./example_lib_proto.zig").MyStruct;

// const ConversionTemplate = struct {
//     py_to_ctype: []const u8,
//     ctype_to_py: []const u8,
// };

// const PyString = extern struct {
//     value: [*:0]u8, // will be exposed into python as a _field_
//     conv_template: ConversionTemplate = .{
//         .py_to_ctype = "{{arg_ident}} = {{arg_ident}}.encode('utf-8')",
//         .ctype_to_py = "{{res_ident}} = {{res_ident}}.decode('utf-8')",
//     },
// };

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
            const libzigpy_ident = "codegenstruct_" ++ decl.name;
            var method_data = templ.MethodData.init(alloc, libzigpy_ident);

            const user_fn = @field(targetStruct, decl.name);
            const user_fn_info = @typeInfo(@TypeOf(user_fn));
            std.debug.assert(user_fn_info == .Fn);
            inline for (user_fn_info.Fn.params, 0..) |param, i| {
                const arg_ident = std.fmt.comptimePrint("arg{}", .{i});
                try method_data.addArg(param.type.?, arg_ident);
            }
            try template_data.addMethod(&method_data);
        }
    }

    const rendered = try template_data.render();

    const output_file_path = struct_ident ++ "_proto.py";
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch unreachable;
    defer output_file.close();
    try output_file.writeAll(rendered);
}

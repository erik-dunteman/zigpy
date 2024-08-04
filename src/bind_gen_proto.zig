const std = @import("std");
const print = std.debug.print;
const templ = @import("./template_proto.zig");

const ConversionTemplate = struct {
    py_to_ctype: []const u8,
    ctype_to_py: []const u8,
};

const PyString = extern struct {
    value: [*:0]u8, // will be exposed into python as a _field_
    conv_template: ConversionTemplate = .{
        .py_to_ctype = "{{arg_ident}} = {{arg_ident}}.encode('utf-8')",
        .ctype_to_py = "{{res_ident}} = {{res_ident}}.decode('utf-8')",
    },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const struct_ident = "MyStructProto";

    var template_data = templ.TemplateData.init(alloc, struct_ident);
    try template_data.addField("a", "c_int");
    try template_data.addField("b", "c_int");

    var method = templ.Method.init(alloc, "codegenstruct_sum");
    try method.addArg(i32, "a");
    try method.addArg(i32, "b");
    try template_data.addMethod(&method);

    const rendered = try template_data.render();

    const output_file_path = struct_ident ++ "_proto.py";
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch unreachable;
    defer output_file.close();
    try output_file.writeAll(rendered);
}

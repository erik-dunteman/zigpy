const std = @import("std");
const builtin = @import("builtin");
const mustache = @import("vendors/mustache-zig/src/mustache.zig");
const ZigType = @import("./types.zig").ZigType;
const get_template = @import("./template.zig").get_template;

const FieldData = struct {
    ident: []const u8,
    ctype: []const u8,
    py_type: []const u8,
};
const FieldRenderable = FieldData;

const CTypeImportData = struct {
    ident: []const u8,
};
const CTypeImportRenderable = CTypeImportData;

const ArgData = struct {
    zig_type: ZigType,
    ctype: []const u8,
    py_type: []const u8,
    ident: []const u8,
    is_self: bool = false,
};
const ArgRenderable = ArgData;

pub const MethodData = struct {
    alloc: std.mem.Allocator,
    struct_ident: []const u8,
    libzigpy_ident: []const u8,
    ident: []const u8,
    res_ctype: []const u8 = undefined,
    res_py_type: []const u8 = undefined,
    args: std.ArrayList(ArgData),

    pub fn init(alloc: std.mem.Allocator, struct_ident: []const u8, ident: []const u8) !MethodData {
        const libzigpy_ident = try std.fmt.allocPrint(alloc, "codegenstruct_{s}", .{ident});
        return MethodData{ .alloc = alloc, .struct_ident = struct_ident, .ident = ident, .libzigpy_ident = libzigpy_ident, .args = std.ArrayList(ArgData).init(alloc) };
    }
    pub fn addArg(self: *MethodData, comptime zig_type: type, ident: []const u8) !void {
        const zt = ZigType.fromType(zig_type);
        try self.args.append(.{
            .zig_type = zt,
            .ident = ident,
            .ctype = zt.toCType(),
            .py_type = zt.toPyType(),
        });
    }

    pub fn addSelfArg(self: *MethodData, ident: []const u8, is_ptr: bool) !void {
        // for the case where user is calling a method on self
        const zt: ZigType = if (is_ptr) .self_ptr else .self;
        var ctype = zt.toCType();
        var py_type = zt.toPyType();

        // ctype and py_type have to be rendered with the struct_ident
        ctype = try mustache.allocRenderText(self.alloc, ctype, .{ .struct_ident = self.struct_ident });
        py_type = try mustache.allocRenderText(self.alloc, py_type, .{ .struct_ident = self.struct_ident });

        try self.args.append(.{
            .zig_type = zt,
            .ident = ident,
            .ctype = ctype,
            .py_type = py_type,
            .is_self = std.mem.eql(u8, ident, "self"), // special case, we hardcode self in template, so this flag tells us to render it differently
        });
    }

    pub fn addReturnType(self: *MethodData, comptime zig_type: type) !void {
        const zt = ZigType.fromType(zig_type);
        self.res_ctype = zt.toCType();
        self.res_py_type = zt.toPyType();
    }

    pub fn addSelfReturnType(self: *MethodData, is_ptr: bool) !void {
        const zt: ZigType = if (is_ptr) .self_ptr else .self;
        var ctype = zt.toCType();
        var py_type = zt.toPyType();

        // ctype and py_type have to be rendered with the struct_ident
        ctype = try mustache.allocRenderText(self.alloc, ctype, .{ .struct_ident = self.struct_ident });
        py_type = try mustache.allocRenderText(self.alloc, py_type, .{ .struct_ident = self.struct_ident });

        self.res_ctype = ctype;
        self.res_py_type = py_type;
    }
};

// methodData contains an arrayList which is not renderable
// so we need to convert it to a renderable array
pub const MethodRenderable = struct {
    libzigpy_ident: []const u8,
    ident: []const u8,
    res_ctype: []const u8,
    res_py_type: []const u8,
    args: []ArgData, // for rendering
};
fn getMethodRenderables(alloc: std.mem.Allocator, methods: std.ArrayList(MethodData)) ![](MethodRenderable) {
    var method_data = std.ArrayList(MethodRenderable).init(alloc);
    for (methods.items) |method| {
        const method_data_item = MethodRenderable{
            .libzigpy_ident = method.libzigpy_ident,
            .ident = method.ident,
            .res_ctype = method.res_ctype,
            .res_py_type = method.res_py_type,
            .args = method.args.items,
        };
        try method_data.append(method_data_item);
    }
    return method_data.items;
}

// TemplateData is what we'll be building out while inspecting the zig struct
// Its data matches the template
pub const TemplateData = struct {
    alloc: std.mem.Allocator,
    struct_ident: []const u8,
    shared_lib_extension: []const u8,
    fields: std.ArrayList(FieldData),
    ctype_imports: std.ArrayList(CTypeImportData),
    methods: std.ArrayList(MethodData),

    pub fn init(alloc: std.mem.Allocator, struct_ident: []const u8) TemplateData {
        const fields = std.ArrayList(FieldData).init(alloc);
        const ctype_imports = std.ArrayList(CTypeImportData).init(alloc);
        const methods = std.ArrayList(MethodData).init(alloc);

        const shared_lib_extension = switch (builtin.os.tag) {
            .macos => "dylib",
            .linux => "so",
            else => @compileError("unsupported os"),
        };

        return TemplateData{
            .alloc = alloc,
            .struct_ident = struct_ident,
            .shared_lib_extension = shared_lib_extension,
            .fields = fields,
            .ctype_imports = ctype_imports,
            .methods = methods,
        };
    }

    pub fn addField(self: *TemplateData, ident: []const u8, comptime T: type) !void {
        const zt = ZigType.fromType(T);
        const ctype = zt.toCType();
        const py_type = zt.toPyType();
        try self.fields.append(.{
            .ident = ident,
            .ctype = ctype,
            .py_type = py_type,
        });
        try self.assureCTypeImport(ctype);
    }

    pub fn addMethod(self: *TemplateData, method: *MethodData) !void {
        try self.methods.append(method.*);
        for (method.args.items) |arg| {
            try self.assureCTypeImport(arg.ctype);
        }
        try self.assureCTypeImport(method.res_ctype);
    }

    fn assureCTypeImport(self: *TemplateData, ctype: []const u8) !void {
        // ignore imports referring to the self type
        if (std.mem.containsAtLeast(u8, ctype, 1, self.struct_ident)) return;

        var is_imported = false;
        for (self.ctype_imports.items) |c_type_import| {
            if (std.mem.eql(u8, c_type_import.ident, ctype)) {
                is_imported = true;
                break;
            }
        }
        if (!is_imported) {
            try self.ctype_imports.append(.{ .ident = ctype });
        }
    }

    pub fn render(self: *TemplateData) ![]const u8 {
        const template = get_template();
        const template_renderable = .{
            .struct_ident = self.struct_ident,
            .shared_lib_extension = self.shared_lib_extension,
            .fields = self.fields.items,
            .ctype_imports = self.ctype_imports.items,
            .methods = try getMethodRenderables(self.alloc, self.methods),
        };
        return mustache.allocRenderText(self.alloc, template, template_renderable);
    }
};

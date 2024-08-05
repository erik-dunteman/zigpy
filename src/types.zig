// Special types which carry extra pre/post processing logic

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

// Type conversion table
pub const ZigType = union(enum) {
    self, // special case for users referring to their own struct
    self_ptr, // special case for users referring to their own struct
    void,
    i32,
    bool,
    zero_terminated_u8_slice,

    pub fn fromType(comptime T: type) ZigType {
        switch (T) {
            i32 => return .i32,
            bool => return .bool,
            void => return .void,
            [*:0]u8, [*:0]const u8 => return .zero_terminated_u8_slice,
            else => @compileError("unsupported type"),
        }
    }

    pub fn toCType(self: ZigType) []const u8 {
        return switch (self) {
            .i32 => "c_int",
            .bool => "c_int",
            .zero_terminated_u8_slice => "c_char_p",
            .self => "{{struct_ident}}",
            .self_ptr => "POINTER({{struct_ident}})",
            .void => "c_void_p",
        };
    }

    pub fn toPyType(self: ZigType) []const u8 {
        return switch (self) {
            .i32 => "int",
            .bool => "bool",
            .zero_terminated_u8_slice => "bytes", // users are responsible for encoding, else use special String type
            .self => "{{struct_ident}}",
            .self_ptr => "{{struct_ident}}",
            .void => "None",
        };
    }
};

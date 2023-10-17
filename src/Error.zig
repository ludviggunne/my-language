
const std = @import("std");
const Self = @This();
const Token = @import("Token.zig");
const Type = @import("TypeChecker.zig").Type;

pub const Reference = struct {
    line:        []const u8,
    line_number: usize,
    line_index:  usize,
};

stage: enum {
    lexing,
    parsing,
    typechecking,
    constant_folding,
    resolve,
    codegen,
},
where: ?[]const u8 = null,
kind: union(enum) {
    // Lexing
    unexpected_character: []const u8,
    unexpected_token: struct {
        expected: Token.Kind,
        found:    Token.Kind,
    },
    // Parsing
    unexpected_token_oneof: struct {
        expected: []const Token.Kind,
        found:    Token.Kind,
    },
    unexpected_eoi,
    // Type checking
    binary_mismatch: struct {
        left: Type,
        right: Type,
    },
    operator_mismatch: struct {
        expected: Type,
        found:    Type,
    },
    control_flow_mismatch,
    return_mismatch,
    argument_mismatch,
    // Constant foldin
    division_by_zero,
    // Symbol resolution
    redeclaration,
    undeclared_ref,

},

pub fn print(self: *const Self, source: []const u8, writer: anytype) !void {

    try writer.print("Error during {s}: ", .{ @tagName(self.stage), });

    switch (self.kind) {
        .unexpected_token => |v| {
            try writer.print(
                "Unexpected token {s}: expected {s}\n",
                .{
                    @tagName(v.found),
                    @tagName(v.expected),
                }
            );
            try printReference(self.where.?, source, writer);
        },

        .unexpected_token_oneof => |v| {
            try writer.print("Unexpected token {s}: expected one of ", .{ @tagName(v.found), });
            for (v.expected) |expected| {
                try writer.print("{s}, ", .{ @tagName(expected), });
            }
            try writer.print("\n", .{});
            try printReference(self.where.?, source, writer);
        },

        .binary_mismatch => |v| {
            try writer.print(
                "Type mismatch for binary operator: {s} =/= {s}\n",
                .{
                    @tagName(v.left),
                    @tagName(v.right),
                }
            );
            try printReference(self.where.?, source, writer);
        },

        .operator_mismatch => |v| {
            try writer.print(
                "Type mismatch: can't use operator {s} with type {s}\n",
                .{
                    self.where.?,
                    @tagName(v.found),
                },
            );
            try printReference(self.where.?, source, writer);
        },

        .control_flow_mismatch => {
            try writer.print("Type mismatch: condition for control block must be boolean\n", .{});
            try printReference(self.where.?, source, writer);
        },
        
        .return_mismatch => {
            try writer.print("Type mismatch: non-integer in return statement expression\n", .{});
            try printReference(self.where.?, source, writer);
        },
    
        .argument_mismatch => {
            try writer.print("Type mismatch: only integer arguments are allowed\n", .{});
            try printReference(self.where.?, source, writer);
        },

        .division_by_zero => {
            try writer.print("Division by zero\n", .{});
            try printReference(self.where.?, source, writer);
        },

        else => try writer.print("UNIMPLEMENTED ERROR MESSAGE\n", .{}),
    }
}

pub fn reference(where: []const u8, source: []const u8) Reference {
    
    const source_raw: *const u8 = @ptrCast(source);
    const where_raw: *const u8 = @ptrCast(where);
    const offset = @intFromPtr(where_raw) - @intFromPtr(source_raw);

    var line_begin: usize = 0;
    var line_end: usize = source.len;
    var line_number: usize = 1;
    var search_begin = true;
    for (source, 0..) |c, i| {

        if (i == offset) {
            search_begin = false;
        }
        
        if (c == '\n') {
            if (search_begin) {
                line_number += 1;
                line_begin = i + 1;
            } else {
                line_end = i;
                break;
            }
        }
    }

    const line = source[line_begin..line_end];
    const line_index = offset - line_begin;

    return .{
        .line        = line,
        .line_number = line_number,
        .line_index  = line_index,
    };
}

pub fn printReference(where: []const u8, source: []const u8, writer: anytype) !void {

    const ref = reference(where, source);
    try writer.print("Line {d}: {s}\n", .{ ref.line_number, ref.line, }); 
    try writer.print("        ", .{});
    for (0..ref.line_index) |_| try writer.print(" ", .{});
    try writer.print("^\n", .{});
}

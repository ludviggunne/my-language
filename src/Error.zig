
const std = @import("std");
const Self = @This();
const Token = @import("Token.zig");

pub const Reference = struct {
    line:        []const u8,
    line_number: usize,
    line_index:  usize,
};

stage: enum {
    lexing,
    parsing,
    resolve,
    codegen,
},
where: ?[]const u8 = null,
kind: union(enum) {
    unexpected_character: []const u8,
    unexpected_token: struct {
        expected: Token.Kind,
        found:    Token.Kind,
    },
    unexpected_token_oneof: struct {
        expected: []const Token.Kind,
        found:    Token.Kind,
    },
    unexpected_eoi,
    redeclaration,
    undeclared_ref,
},

pub fn print(self: *Self, source: []const u8, writer: anytype) !void {

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
